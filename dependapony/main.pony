use "cli"
use "net"
use "json"
use "http"
use "files"
use "debug"
use "regex"
use "collections"
//use "corral/semver/range"
//use "corral/semver/solver"
//use "corral/semver/utils"
//use "corral/semver/version"

actor Main
  let env: Env
  var mycorral: CorralJson
  var mylock:   LockJson
  var mylocks: Array[CorralDep] val = Array[CorralDep]
  var depmap: Map[String val, Array[(String val, String val, String val)]] = Map[String val, Array[(String val, String val, String val)]]

  new create(env': Env) =>
    env = env'

    let githubactor: GithubActor = GithubActor(TCPConnectAuth(env.root), this)
    mycorral = CorralJson.from_file(FileAuth(env.root), "corral.json")
    mylock   =   LockJson.from_file(FileAuth(env.root), "lock.json")
    try
      env.out.print("Checking against local corral.json and lock.json")
      env.out.print("================================================\n")
      mylocks = mylock.locks("local")?
    end
    for lock in mylocks.values() do
      try
      (var o: String val, var r: String val) =
        GithubTranslations.extract_owner_repo(lock.locator)?
      insert_dep("local", o, r, lock.version)
      else
        Debug.out("Failed to insert: " + lock.string())
      end
    end

    dump_deps("local")

//    try
//      (var owner: String val, var repo: String val) =
//        GithubTranslations.extract_owner_repo("github.com/ponylang/ssl.git")?
//        Debug.out(GithubTranslations.to_latest_package(owner, repo))
//    else
//      Debug.out("Failed to build regex")
//    end
//    githubactor.check_latesturl("https://cultof.show/mock-latest.json")

  fun ref dump_deps(s: String val) =>
    for (o, r, t) in depmap.get_or_else(s, Array[(String val, String val, String val)]).values() do
      Debug.out(s + ": " +
          o + "/" +
          r + " => " +
          t)
    end



  fun ref insert_dep(cur: String val,
    down: String val, repo: String val, vtag: String val) =>
    var array: Array[(String val, String val, String val)] =
      depmap.get_or_else(cur, Array[(String val, String val, String val)])
      array.push((down, repo, vtag))
      depmap.insert(cur, array)


  be data_retrieved(data: String val) =>
    try
      var doc: JsonDoc val = recover val JsonDoc .> parse(data)? end
      let obj = JsonExtractor(doc.data).as_object()?
      var html_url: String val = obj("html_url")? as String val

      (var owner: String val, var repo: String val, var vtag: String val) =
        GithubTranslations.extract_owner_repo_tag(html_url)?
        Debug.out("Latest Release: " +
            owner + "/" +
            repo + " => " +
            vtag)


    else
      env.out.print("JSON response was not parseable")
    end



primitive GithubTranslations
  fun extract_owner_repo(url: String val): (String val, String val) ? =>
    let r = Regex("github\\.com\\/([^/]+)\\/([^/]+)\\.git")?
    let matched = r(url)?
    (matched(1)?, matched(2)?)

  fun extract_owner_repo_tag(url: String val): (String val, String val, String val) ? =>
    Debug.out(url)
    let r = Regex("github\\.com\\/([^/]+)\\/([^/]+)\\/releases\\/tag\\/(.*)")?
    let matched = r(url)?
    (matched(1)?, matched(2)?, matched(3)?)

  fun to_latest_package(owner: String val, repo: String val): String val =>
    "https://api.github.com/repos/" +
    owner +
    "/" +
    repo +
    "/releases/latest"


class CorralJson
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
