use "net"
use "http"
use "debug"
use "ssl/net"

actor GithubActor
  let auth: TCPConnectAuth
  let timeout: U32 = 60
  let main: Main tag

  new create(auth': TCPConnectAuth, main': Main tag) =>
    main = main'
    auth = auth'

  be to_tagged_corral(o: String val, r: String val, t: String val) => None
    let clf = recover val NotifyFactory.create(this, o, r, t) end
    check_url(GithubTranslations.to_tagged_corral(o, r, t), clf)

  be check_latest(o: String val, r: String val) =>
    let clf = recover val NotifyFactory.create(this, o, r, "") end
    check_url(GithubTranslations.to_latest_package(o, r), clf)

  be check_url(url: String val, clf: NotifyFactory val) =>
    var sslctx: SSLContext val =
      recover val SSLContext.>set_client_verify(false) end
    // The Client manages all links.
    let client: HTTPClient = HTTPClient(
      auth,
      clf,
      consume sslctx
      where keepalive_timeout_secs = timeout
    )

    try
      let req = Payload.request("GET", URL.valid(url)?)
      req("User-Agent") = "dependapony v0.0.1"
      var sentreq = client(consume req)?
    else
      Debug.out("Request send failed")
    end

  be cancelled() => Debug.out("Got cancelled")
  be failed(f: HTTPFailureReason) => Debug.out("Got failed")
  be have_response(p: Payload val, o: String val, r: String val, t: String val) =>
    var rv: String iso = recover iso String end
    try
      let body = p.body()?
      for piece in body.values() do
        rv.append(piece)
      end
//      Debug.out(consume rv)
    end
    main.data_retrieved(consume rv, o, r, t)

  be have_body(b: ByteSeq val) => Debug.out("Got have_body")
  be finished() => Debug.out("Got finished")




class NotifyFactory is HandlerFactory
  """
  Create instances of our simple Receive Handler.
  """
  let _main: GithubActor
  let owner: String val
  let repo: String val
  let vtag: String val

  new iso create(main': GithubActor, o: String val, r: String val, t: String val) =>
    _main = main'
    owner = o
    repo = r
    vtag = t

  fun apply(session: HTTPSession): HTTPHandler ref^ =>
    HttpNotify.create(_main, session, owner, repo, vtag)

class HttpNotify is HTTPHandler
  """
  Handle the arrival of responses from the HTTP server.  These methods are
  called within the context of the HTTPSession actor.
  """
  let _main: GithubActor
  let _session: HTTPSession
  let owner: String val
  let repo: String val
  let vtag: String val

  new ref create(main': GithubActor, session: HTTPSession, o: String val, r: String val, t: String val) =>
    _main = main'
    _session = session
    owner = o
    repo = r
    vtag = t

  fun ref apply(response: Payload val) =>
    """
    Start receiving a response.  We get the status and headers.  Body data
    *might* be available.
    """
    _main.have_response(response, owner, repo, vtag)

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
