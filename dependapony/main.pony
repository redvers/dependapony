use "cli"
use "net"
use "json"
use "http"
use "files"
use "debug"
use "regex"
use "collections"

actor Main
  let env: Env
  var mycorral: CorralJson
  var mylock:   LockJson
  var mylocks: Array[CorralDep] val = Array[CorralDep]
  var depmap: Map[String val, Array[(String val, String val, String val)]] = Map[String val, Array[(String val, String val, String val)]]
  var githubactor: GithubActor tag
  var latest: Map[String val, String val] = Map[String val, String val]
  var githubcount: USize = 0

  new create(env': Env) =>
    env = env'

    githubactor = GithubActor(TCPConnectAuth(env.root), this)
    mycorral = CorralJson.from_file(FileAuth(env.root), "corral.json")
    mylock   =   LockJson.from_file(FileAuth(env.root), "lock.json")
    try
      env.out.print("Checking against local lock.json")
      env.out.print("================================")
      mylocks = mylock.locks("local")?
    end
    for lock in mylocks.values() do
      try
      (var o: String val, var r: String val) =
        GithubTranslations.extract_owner_repo(lock.locator)?
      insert_dep("local", o, r, lock.version)
      githubcount = githubcount + 1
      githubactor.check_latest(o, r)
      else
        Debug.out("Failed to insert: " + lock.string())
      end
    end


  fun ref dump_deps(s: String val) =>
    for (o, r, t) in depmap.get_or_else(s, Array[(String val, String val, String val)]).values() do
      env.out.print(s + ": " +
          o + "/" +
          r + " => " +
          t + " [" +
          try latest(o + "/" + r)? else "Not Found" end +
          "]")
    end



  fun ref insert_dep(cur: String val,
    down: String val, repo: String val, vtag: String val) =>
    var array: Array[(String val, String val, String val)] =
      depmap.get_or_else(cur, Array[(String val, String val, String val)])
      array.push((down, repo, vtag))
      depmap.insert(cur, array)


  be data_retrieved(data: String val, po: String val, pr: String val, pt: String val) =>
    githubcount = githubcount - 1
    try
      var doc: JsonDoc val = recover val JsonDoc .> parse(data)? end
      let obj = JsonExtractor(doc.data).as_object()?
      try
        var html_url: String val = obj("html_url")? as String val

        (var owner: String val, var repo: String val, var vtag: String val) =
          GithubTranslations.extract_owner_repo_tag(html_url)?
          latest.insert(po+"/"+pr, vtag)
          // ACTIVATE
        githubcount = githubcount + 1
        githubactor.to_tagged_corral(owner, repo, vtag)
      else
        var cj: CorralJson = CorralJson.from_text(data)
        try
          for f in cj.deps()?.values() do
            (var o: String val, var r: String val) =
              GithubTranslations.extract_owner_repo(f.locator)?
            insert_dep(po+"/"+pr+":"+pt, o, r, f.version)

            if (depmap.contains(o+"/"+r+":"+f.version)) then
              Debug.out(o+"/"+r+":"+ f.version + " is already present")
            else
              githubcount = githubcount + 1
              githubactor.check_latest(o, r)
            end
          end
        else
          Debug.out("We failed to parse cj")
        end
      end
      if (githubcount == 0) then
        dump_deps("local")
        for f in depmap.keys() do
          if (f == "local") then continue end
          env.out.print("")
          dump_deps(f)
        end
      end


    else
      env.out.print("JSON response was not parseable")
    end



primitive GithubTranslations
  fun extract_owner_repo(url: String val): (String val, String val) ? =>
    let r = Regex("github\\.com\\/([^/]+)\\/([^/]+)\\.git")?
    let matched = r(url)?
    (matched(1)?, matched(2)?)

  fun extract_owner_repo_tag(url: String val): (String val, String val, String val) ? =>
    let r = Regex("github\\.com\\/([^/]+)\\/([^/]+)\\/releases\\/tag\\/(.*)")?
    let matched = r(url)?
    (matched(1)?, matched(2)?, matched(3)?)

  fun to_latest_package(owner: String val, repo: String val): String val =>
    "https://api.github.com/repos/" +
    owner +
    "/" +
    repo +
    "/releases/latest"

  fun to_tagged_corral(o: String val, r: String val, t: String val): String val =>
    "https://raw.githubusercontent.com/" +
        o + "/" +
        r + "/refs/tags/" +
        t + "/corral.json"



class CorralJson
  var valid: Bool = false
  var contents: String val = ""
  var owner: String val = ""
  var repo: String val = ""
  var vtag: String val = ""

  new from_file(auth: FileAuth, filename: String val) =>
    var fp: FilePath = FilePath(auth, filename)
    match OpenFile(fp)
    | let file: File =>
      contents = file.read_string(file.size())
      valid = true
    else
      valid = false
    end

  new from_text(s: String val) => None
    contents = s

  fun deps(): Array[CorralDep] val ? =>
    let rv: Array[CorralDep] trn = recover trn Array[CorralDep] end
    let doc: JsonDoc val = recover val
      try
        JsonDoc .> parse(contents)?
      else
        Debug.out("We failed to parse jsonfile: ")
        Debug.out(contents)
        error
      end
    end

    for f in JsonExtractor(doc.data)("deps")?.as_array()?.values() do
      let jo = JsonExtractor(f).as_object()?
      let corraldep: CorralDep iso = recover iso CorralDep end
      corraldep.locator = JsonExtractor(jo("locator")?).as_string()?
      match JsonExtractor(jo("version")?).as_string_or_none()?
      | let x: None => corraldep.version = ""
      | let x: String val => corraldep.version = x
      end
      rv.push(consume corraldep)
    end
    consume rv





class LockJson
  var valid: Bool = false
  var contents: String val = ""
  new from_file(auth: FileAuth, filename: String val) =>
    var fp: FilePath = FilePath(auth, filename)
    match OpenFile(fp)
    | let file: File =>
      contents = file.read_string(file.size())
      valid = true
    else
      valid = false
    end

  fun locks(parentdep: String val): Array[CorralDep] val ? =>
    let rv: Array[CorralDep] trn = recover trn Array[CorralDep] end
    let doc: JsonDoc val = recover val
      try
        JsonDoc .> parse(contents)?
      else
        Debug.out("We failed to parse jsonfile: ")
        Debug.out(contents)
        error
      end
    end

    for f in JsonExtractor(doc.data)("locks")?.as_array()?.values() do
      let jo = JsonExtractor(f).as_object()?
      let corraldep: CorralDep iso = recover iso CorralDep end
      corraldep.locator = JsonExtractor(jo("locator")?).as_string()?
      match JsonExtractor(jo("revision")?).as_string_or_none()?
      | let x: None => corraldep.version = ""
      | let x: String val => corraldep.version = x
      end
      rv.push(consume corraldep)
    end
    consume rv


class CorralDep
  var locator: String val = ""
  var version: String val = ""

  fun string(): String val => locator + " => " + version



primitive NotGithub
