# The progress pattern for error reporting

This one is really simple, but I didn’t see it written down anywhere and I find it extremely useful.

## Problem

Let’s say you have a function for connecting to a WebSocket. This includes a bunch of steps:
you need to resolve the hostname, bind a socket, create a TCP connection, do a TLS handshake
and then do a WebSocket handshake. You can write it in Rust like this:

```rust
pub async fn connect_ws(local_addr: SocketAddr, host: &str) -> Result<WebSocket> {
    let peer_addr = resolve(host)?;
    let socket = bind(local_addr)?;
    socket.connect(peer_addr)?;
    let tls_connection = tls_handshake(host, socket).await?;
    let ws_connection = ws_handshake(tls_connection).await?;
    ws_connection
}
```

Note the `?` on nearly every line — this operation involves doing _a lot_ of fallible I/O.

One natural requirement for our function could be “when failed, print a log message”.
A naive solution leads to bad logs:

```rust
match connect_ws(local_addr, host) {
    Ok(ws) => use_websocket(ws),
    Err(err) => {
        error!("something went wrong while connecting to WS: {err}", host = host);
    }
}
```

This message lacks details. Ideally, we’d like to know all the details about the situation:
what was the `peer_addr`? what was the chosen local port if binding to port `0`?
which step actually failed?

A common solution is to wrap all the errors with extra data, like this:

```rust
pub async fn connect_ws(local_addr: SocketAddr, host: &str) -> Result<WebSocket> {
    let peer_addr = resolve(host).map_err(|err| ResolveError::new(err, host))?;
    let socket = bind(local_addr).map_err(|err| BindError::new(err, host, peer_addr))?;
    let bound_addr = socket.local_addr();
    // ^ this actually can fail btw, but we’ll pretend it can’t for brevity
    socket.connect(peer_addr).map_err(|err| ConnectError::new(err, host, peer_addr, bound_addr))?;
    let tls_connection = tls_handshake(host, socket)
        .map_err(|err| TlsError::new(err, host, peer_addr, bound_addr))
        .await?;
    let ws_connection = ws_handshake(tls_connection)
        .map_err(|err| WsError::new(err, host, peer_addr, bound_addr))
        .await?;
    ws_connection
}
```

It kinda works, but it’s extremely repetitive and fails to accommodate our next requirement:
we want to be able to wrap our connection in `timeout()` while retaining information on which
particular operation timed out. As `timeout()` creates a new error, it doesn’t retain
any additional info we painstakingly added.

(One other option would be to manually check every operation in `connect_ws()` and log on error:

```rust
socket.connect(peer_addr).map_err(|err| {
    error!(
        "failed to connect: {err}",
        host = host, peer_addr = peer_addr, local_addr = bound_addr,
    );
    err
})?;
```

That’s even more cumbersome and still isn’t compatible with timeouts)

## Solution

Instead of trying to stuff all the info into an error, let’s make a separate type:

```rust
#[non_exhaustive]
#[derive(Default)]
pub struct ConnectionProgress {
    pub local_addr: Option<SocketAddr>,
    pub peer_addr: Option<SocketAddr>,
    pub did_connect: bool,
    pub did_tls: bool,
}
```

and pass it as an outparam:

```rust
pub async fn connect_ws(
    local_addr: SocketAddr, host: &str, progress: &mut ConnectionProgress,
) -> Result<WebSocket> {
    let peer_addr = resolve(host)?;
    progress.peer_addr = Some(peer_addr);
    let socket = bind(local_addr)?;
    progress.local_addr = Some(socket.local_addr());
    socket.connect(peer_addr)?;
    progress.did_connect = true;
    let tls_connection = tls_handshake(host, socket).await?;
    progress.did_tls = true;
    let ws_connection = ws_handshake(tls_connection).await?;
    ws_connection
}
```

This is _much_ less repetitive, doesn’t require complicated error types and works perfectly well with timeouts:

```rust
let mut progress = ConnectionProgress::default();
let report_error = |err, progress| {
    error!(
        "error while connecting to WS: {err}",
        host = host,
        local_addr = progress.local_addr,
        peer_addr = progress.peer_addr,
        did_connect = progress.did_connect,
        did_tls = progress.did_tls,
    );
};

match timeout(connect_ws(local_addr, host, &mut progress)).await {
    Ok(Ok(ws)) => use_websocket(ws),
    Err(timeout) => report_error(Error::Timeout, progress),
    Ok(Err(err)) => report_error(err, progress),
}
```

Additionally, this pattern plays well with retries: you can pass a `&mut Vec<ConnectionProgress>`
(or `&mut SmallVec<[ConnectionProgress; MAX_RETRIES]>` if you want to avoid an allocation)
and get all the information without losing `?` in the `connect_ws()` function or `timeout()` compatibility:

```rust
pub struct ConnectionProgress {
    // ... old fields ...
    pub error: Option<Error>, // new field!
}

pub async fn connect_ws_with_retries(
    retries: usize,
    local_addr: SocketAddr,
    host: &str,
    progress: &mut Vec<ConnectionProgress>,
) -> Result<WebSocket> {
    for _ in 0..retries {
        // we need to push first so progress is retained if anything times out
        progress.push(ConnectionProgress::default());
        // ideally, we’d have like `.push_and_get_last_mut()`, but whatever
        let attempt_progress = progress.last_mut().unwrap();
        match connect_ws(local_addr, host, &mut *attempt_progress).await {
            Ok(ws) => return Ok(ws),
            Err(err) => attempt_progress.error = Some(err),
        }
    }
    Err(Error::RetriesExceeded)
}
```

We _still_ can use it with `timeout()` just as easily and we get full data on every connection attempt,
including information on where the last attempt timed out (if it did).

Alternatively, if you’d like to get logs on failed attempts immediately instead of after exhausting
all the attempts, you can use a `Drop` guard:

```rust
struct LogGuard<'a> {
    host: &'a str,
    progress: ConnectionProgress,
    error: Option<Error>,
}

impl Drop for LogGuard {
    fn drop(&mut self) {
        let error = error.unwrap_or(Error::Timeout);
        error!(
            "error while connecting to WS: {error}",
            host = self.host,
            local_addr = self.progress.local_addr,
            peer_addr = self.progress.peer_addr,
            did_connect = self.progress.did_connect,
            did_tls = self.progress.did_tls,
        );
    }
}


for _ in 0..retries {
    let mut guard = LogGuard { host, progress: <_>::default(), error: None };
    match connect_ws(local_addr, host, &mut guard.progress).await {
        Ok(ws) => {
            // don't log an error, it didn't happen
            mem::forget(guard);
            return Ok(ws);
        }
        // guard will get dropped (and produce a log) before next iteration
        Err(err) => guard.error = Some(err),
    }
}
```

Timeout will drop the guard, causing a log with `Error::Timeout`.

## Closing thoughts

I think this pattern works really well for error handling in non-trivial functions.
It allows you to extract all the information you need while being relatively brief,
`timeout()`- and retry-friendly.

I didn’t name the post “...for error reporting in Rust”, because I think it applies well to other languages,
especially Zig (which doesn’t allow you to pass extra data in first-class errors at all)
or C (which doesn't have first-class errors, so you kinda can do tagged unions, but mostly people just use error codes)
or languages that use exceptions (so you can avoid having to catch and rethrow all the time).

I’m most certainly not the first person to think of this, but I’ve never actually seen anything
written about this pattern, so I decided to write it down here.

Thanks to [@WaffleLapkin] for proofreading this post!

[@WaffleLapkin]: https://github.com/WaffleLapkin/
