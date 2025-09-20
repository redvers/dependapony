use "net"
use "http"
use "debug"
use "ssl/net"

actor GithubActor
  let auth: TCPConnectAuth
  let timeout: U32 = 60
  let client: HTTPClient
  let main: Main tag

  new create(auth': TCPConnectAuth, main': Main tag) =>
    main = main'
    auth = auth'

    var sslctx: SSLContext val =
      recover val SSLContext.>set_client_verify(false) end

    let dumpMaker = recover val NotifyFactory.create(this) end

    // The Client manages all links.
    client = HTTPClient(
      auth,
      dumpMaker,
      consume sslctx
      where keepalive_timeout_secs = timeout
    )

  be check_latest(url: String val) =>
    try
      (var owner: String val, var repo: String val) =
        GithubTranslations.extract_owner_repo(url)?
        Debug.out(GithubTranslations.to_latest_package(owner, repo))
//        check_latesturl(GithubTranslations.to_latest_package(owner, repo))

    else
      Debug.out("We failed with: " + url)
    end

  be check_latesturl(url: String val) =>
    try
      let req = Payload.request("GET", URL.valid(url)?)
      req("User-Agent") = "dependapony v0.0.1"
      var sentreq = client(consume req)?
    else
      Debug.out("Request send failed")
    end

  be cancelled() => Debug.out("Got cancelled")
  be failed(f: HTTPFailureReason) => Debug.out("Got failed")
  be have_response(r: Payload val) => Debug.out("Got have_response: " + r.status.string())
    var rv: String iso = recover iso String end
    try
      let body = r.body()?
      for piece in body.values() do
        rv.append(piece)
      end
//      Debug.out(consume rv)
    end
    main.data_retrieved(consume rv)

  be have_body(b: ByteSeq val) => Debug.out("Got have_body")
  be finished() => Debug.out("Got finished")




class NotifyFactory is HandlerFactory
  """
  Create instances of our simple Receive Handler.
  """
  let _main: GithubActor

  new iso create(main': GithubActor) =>
    _main = main'

  fun apply(session: HTTPSession): HTTPHandler ref^ =>
    HttpNotify.create(_main, session)

class HttpNotify is HTTPHandler
  """
  Handle the arrival of responses from the HTTP server.  These methods are
  called within the context of the HTTPSession actor.
  """
  let _main: GithubActor
  let _session: HTTPSession

  new ref create(main': GithubActor, session: HTTPSession) =>
    _main = main'
    _session = session

  fun ref apply(response: Payload val) =>
    """
    Start receiving a response.  We get the status and headers.  Body data
    *might* be available.
    """
    _main.have_response(response)

  fun ref chunk(data: ByteSeq val) =>
    """
    Receive additional arbitrary-length response body data.
    """
    _main.have_body(data)

  fun ref finished() =>
    """
    This marks the end of the received body data.  We are done with the
    session.
    """
    _main.finished()
    _session.dispose()

  fun ref cancelled() =>
    _main.cancelled()

  fun ref failed(reason: HTTPFailureReason) =>
    _main.failed(reason)
