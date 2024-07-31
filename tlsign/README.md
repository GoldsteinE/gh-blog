# The tale of tlsign

All the code of the final implementation is available at [GoldsteinE/tlsign].

[GoldsteinE/tlsign]: https://github.com/GoldsteinE/tlsign

## Background

While procrasinating on Lobsters, I encountered a post titled [Please Don’t Share Our Links on Mastodon][problem].
It successfully clickbaited me, so I’ve read it. Basically, the problem is generating link previews:
every Mastodon server refetches the link to regenerate preview, which leads to a spike of traffic whenever a post is shared.
There’re a lot of Mastodon servers, so this can generate quite a bit of traffic.

Naturally, there was an old [GitHub issue] linked to the post. One comment caught my eye:

> An alternative: relying on [Signed HTTP Exchanges] (not to be confused with HTTP Signatures)
>
> ...

“That’s weird”, I thought, “basically all the HTTP exchanges are already signed, why would you need a new spec for that?”

And so I plunged into a rabbit hole of trying to actually use these signatures.

[problem]: https://news.itsfoss.com/mastodon-link-problem/
[GitHub issue]: https://github.com/mastodon/mastodon/issues/4486
[Signed HTTP Exchanges]: https://wicg.github.io/webpackage/draft-yasskin-http-origin-signed-responses.html

## Concept

The idea is very simple: most websites support HTTPS. If you just record all the data sent between you and the website,
you can then replay this record and so verify that the page was really served by this site.
This approach works around a need to actually implement TLS, which I was very reluctant to do because
it’s famously complicated. We just record some bytes and then reuse these bytes, no TLS understanding needed.

There’s one problem with this approach: it requires TLS implementation to be deterministic, which it normally isn’t.
TLS uses a lot of random data, so we can’t just record `curl https://example.com` and then feed `curl` recorded data:
it (or, rather, OpenSSL it uses to speak TLS) will generate new random numbers, so TLS will break.

(This post is partly a chronicle of my failures; if you just want to read the final solution
skip to [Why not just wrap curl?](#why-not-just-wrap-curl), and if you only want to see
the conclusion, skip to [Results and future work](#results-and-future-work)).

## Whatever, let’s just configure rustls so it uses our random numbers

[rustls] is quite configurable. You can [provide your own crypto implementation][CryptoProvider],
your own [clock] (which is also quite convenient if the exchange ends up depending on the current time),
and, most promisingly, your own [source of randomness]. I’ve quickly implemented a `CryptoProvider`,
plugged it in, and nope, of course it’s not that simple.

rustls docs point out the problem:

> This is used for all randomness required by rustls, but not necessarily randomness required by the underlying cryptography library.
> For example: `SupportedKxGroup::start()` requires random material to generate an ephemeral key exchange key,
> but this is not included in the interface with rustls: it is assumed that the cryptography library provides for this itself.

Welp, that’s inconvenient. Whatever, let’s just wrap the cryptography library so it consumes our random.
There’re two supported crypto providers in rustls: aws-lc-rs and ring. I’ve chosen to wrap ring,
because awc-lc-rs provider actually [reuses quite a bit of ring][awc-lc-rs-ring] and I can’t be bothered
to hack on *two* cryptography libraries.

Thankfully, ring [allows you to pass `&dyn SecureRandom`][ring-random], so we can just implement
it for our type and haha nope it’s sealed. Why is it sealed.

I forked ring locally to unseal the trait and hacked on it for some more time, but after
further experimentation I realized that patching ring to use my random generator everywhere
is slow, arduous and not very fun, so I took a step back.

All these random generators are seeded from `getrandom()`, it would be much easier to just patch that.

[rustls]: https://github.com/rustls/rustls
[CryptoProvider]: https://docs.rs/rustls/0.23.12/rustls/crypto/struct.CryptoProvider.html
[clock]: https://docs.rs/rustls/0.23.12/rustls/time_provider/trait.TimeProvider.html
[source of randomness]: https://docs.rs/rustls/0.23.12/rustls/crypto/struct.CryptoProvider.html#structfield.secure_random
[awc-lc-rs-ring]: https://github.com/rustls/rustls/blob/1177a465680cfac8c2a4b7217758d488d5d840c4/rustls/src/crypto/aws_lc_rs/mod.rs#L25-L32
[ring-random]: https://github.com/briansmith/ring/blob/7c0024abaf4fd59250c9b79cc41a029aa0ef3497/src/rsa/keypair.rs#L527

## Let’s just patch `getrandom()` and move on

Patching `getrandom()` is trivial, so I won’t linger on this part here;
I just wrote a little crate and used `patch.crates-io` to use it instead of the real `getrandom`.

rustls doesn’t care about underlying transport. It accepts `impl Read + Write`
(or even `impl Read` and `impl Write` separately)
and provides `impl Read` and `impl Write` with plaintext data.
Normally, the underlying transport is a socket, so `Read::read()` is an actual `read(2)`,
and `Write::write()` is an actual `write(2)`. I can record all the syscalls and then replay
them by passing a custom implementation of `Read + Write`. I quickly sketched an implementation:

```rust
struct Transcript {
    //        vvv 1 element = 1 byte
    read: Vec<Vec<u8>>,
    //    ^^^ 1 element = 1 syscall
    write: Vec<Vec<u8>>,
}

#[derive(Debug)]
enum Socket {
    Real {
        socket: TcpStream,
        transcript: Arc<Mutex<Transcript>>,
        // ^ the other side of this `Arc<_>` is stored outside
        //   so we can extract and save `Transcript` later.
    },
    Emulated {
        transcript: Transcript,
        read_cursor: usize,
        write_cursor: usize,
    },
}
```

I think this one could’ve worked, but I was getting a weird bug: rustls was returning EAGAIN
from `.read()`, but refused to consume any more bytes in `.read_tls()`. I was really tired
from fighting with rustls at that moment, so I decided to take another step back.

(Full code of this attempt is available in [./tlsign-sad](./tlsign-sad). I never edited it, so it’s quite ugly)

## Why not just wrap curl?

We don’t really need to tinker with rustls. At the end of the day, HTTP client is doing some syscalls,
and if we hook these syscalls so they’re deterministic, we can make any HTTP client deterministic.

There’re a few ways of hooking syscalls. The simplest one is using `LD_PRELOAD`, but that actually
hooks libc wrappers over syscalls and not syscalls themselves, so it’s not very robust. 
I’ve quickly checked that it doesn’t prevent curl (or rather OpenSSL) from getting random bytes
and moved on.

The proper way of hooking syscalls is `ptrace(2)`. It’s a syscall used by debuggers, strace and
other stuff that needs a low-level control over another process.
It has a lot of features, most of which we don’t need, but the one that’s important for us
is that it’ll stop the tracee and give us control every time it enters or exits a syscall.
The plan is simple: when `getrandom()` exits, we’ll fill the buffer with nice predictable randomness.

(The code below will be written in C.
I find using raw syscalls from Rust to be cumbersome more often than not,
and it also increases the portability of our solution)

### By the way, how do we get predictable randomness?

By running a CSPRNG with a fixed seed. libsodium provides one, and I’m very much
not implementing a CSPRNG myself, so we’ll just use that:

```c
typedef unsigned char seed_t[randombytes_SEEDBYTES];

void getrandom_impl(seed_t seed, void* buf, size_t size) {
    seed_t new_seeds[2];
    // Split a seed into two: one will be used for this request,
    // and one will be saved for later.
    randombytes_buf_deterministic(new_seeds, sizeof(new_seeds), seed);
    // Save one of the seeds for later:
    memcpy(seed, new_seeds[0], sizeof(seed_t));
    // Fullfill the request:
    randombytes_buf_deterministic(buf, size, new_seeds[1]);
}
```

### Okay, let’s trace a process!

The easiest way to trace a process it to make it call `ptrace(PTRACE_TRACEME)`
and then call `exec*()`. This way it’ll stop on exec and wait for us to tell it to
move forwards:

```c
pid_t child = fork();
if (child == 0) {
    // cut: some argument wrangling
    ptrace(PTRACE_TRACEME, 0, 0, 0);
    //                     ^  ^  ^ unused, can be anything
    execvpe(argv[1], args, envp);
    // `execvpe()` never returns on success.
    // If we reached this point, an error has occured.
    perror("execvpe");
    return 1;
}
```

And now we’re ready to intercept signals.
The main loop of our program will be quite simple: we wait for the tracee to stop,
check if we need to do something with the current syscall, and then tell it to continue
until next syscall:

```c
int wstatus;
// We'll store info about the syscall here.
struct ptrace_syscall_info syscall_info;
for (;;) {
    // Wait for something to happen with our child.
    waitpid(child, &wstatus, 0);
    // If it exited, we’re done. Return the result to caller.
    if (WIFEXITED(wstatus)) {
        return WEXITSTATUS(wstatus);
    }
    // If it died because of a signal, do the same.
    if (WIFSIGNALED(wstatus)) {
        return -WTERMSIG(wstatus);
    }
    // Otherwise it stopped.
    if (WIFSTOPPED(wstatus)) {
        // If it stopped because of a syscall...
        if (WSTOPSIG(wstatus) == SIGTRAP|0x80) {
            // (we’ll discuss this part ^^^^^ in a moment)
            // Try to fetch syscall info:
            int res = ptrace(
                PTRACE_GET_SYSCALL_INFO, child,
                sizeof(struct ptrace_syscall_info), &syscall_info
            );
            // And exit if it failed:
            if (res == -1) {
                perror("ptrace(PTRACE_GET_SYSCALL_INFO)");
                return 1;
            }
            /* our syscalls hooks will be here */
        }
        // But for now let’s continue the child until the next syscall:
        if (ptrace(PTRACE_SYSCALL, child, 0, 0) == -1) {
        //                                ^  ^ unused
            // Returning an error if it failed.
            perror("ptrace(PTRACE_SYSCALL)");
            return 1;
        }
    }
}
```

There’s one little weirdness here: by default there’s no way to distinguish a process
that received `SIGTRAP` from a process that paused because it hit a syscall.
To fix this we need to set the `TRACESYSGOOD` option: it changes stop signal from
`SIGTRAP` to `SIGTRAP|0x80`.
The same option allows us to use `PTRACE_GET_SYSCALL_INFO`.

As far as I’m aware, there’s no way to set ptrace options until the tracee is stopped,
so let’s just do it on the first iteration of our loop:

```c
bool did_setoptions = false;
for (;;) {
    // cut: waitpid, WIFEXITED, WIFSIGNALED
    if (WIFSTOPPED(wstatus)) {
        // If we didn’t enable `TRACESYSGOOD` already...
        if (!did_setoptions) {
            // ...try to do it...
            if (ptrace(PTRACE_SETOPTIONS, child, 0, PTRACE_O_TRACESYSGOOD) == -1) {
                // ...or return an error.
                perror("ptrace(PTRACE_SETOPTIONS)");
                return 1;
            }
            did_setoptions = true;
        }
    }
}
```

### Patching `getrandom(2)`

You may know that as “everything is a file” on Linux, the canonical source of randomness is `/dev/urandom` ([not `/dev/random`!][not-dev-random]).
You may also know that that’s mostly a legacy interface and modern programs usually just use the `getrandom(2)` syscall.
That’s very convenient for our purposes since this way we don’t need to detect reads from `/dev/urandom`:
we can just patch a single syscall with a very simple interface:

```c
ssize_t getrandom(void* buf, size_t buflen, unsigned int flags);
```

Even better, we only care about two things here: `buf` to write our random data and the return value,
which signifies how many bytes kernel had written (we could also just ignore that and write `buflen` bytes).

We want to write our bytes when syscall is about to return to the tracee so the kernel doesn’t overwrite
the buffer with actual randomness. Unfortunately, syscall number and arguments are only available
on syscall *entry*, so we’ll have to handle both:

```c
// Somewhere above the loop:
const char* last_syscall = "<not available>";
// Syscall can’t have more than 6 args:
uint64_t last_args[6] = { 0 };

// Inside our syscall handling code:
switch (syscall_info.op) {
    case PTRACE_SYSCALL_INFO_ENTRY:
        // I don’t want to deal with syscall numbers.
        // Names are nice and printable, albeit somewhat slower.
        last_syscall = resolve_syscall_name(syscall_info.entry.nr);
        memcpy(last_args, syscall_info.entry.args, 48);
        break;
    case PTRACE_SYSCALL_INFO_EXIT:
        if (strcmp(last_syscall, "getrandom") == 0) {
            /* faking getrandom here */
        }
        break;
}
```

(**Q:** Wait, how is `resolve_syscall_name()` defined?

**A:**
```c
const char* resolve_syscall_name(int nr) {
    switch (nr) {
        case 0: return "read";
        case 1: return "write";
        // ...
    }
}
```

**Q:** *Surely* there’s a better way to do it?

**A:** \*sigh\*)

The only task remaining is to actually write some fake randomness.
Technically, `ptrace` provides `PTRACE_POKEDATA`, but its API is very cumbersome:
it can only write full words at word-aligned addresses and only one at a time.

We’ll use much more sensible `process_vm_writev(2)` instead (thanks to [@feedab1e] for pointing it out!):

```c
// Use the syscall return value to determine how many bytes we need to write.
size_t amount = syscall_info.exit.rval;
// Allocate a temporary buffer for our random bytes.
void* tmp = malloc(amount);
getrandom_impl(seed, tmp, amount);
//             ^ seed is in/out param, so it gets updated by the call
struct iovec local = { tmp, amount };
struct iovec remote = { (void*) last_args[0], amount };
//                      ^ pointer to buffer is a first arg of the syscall
if (process_vm_writev(
    /* pid = */ child,
    /* local_iov = */ &local, /* liovcnt = */ 1,
    //       how many buffers we want to copy ^
    /* remote_iov = */ &remote, /* riovcnt = */ 1,
    //               the same on the other side ^
    /* flags = */ 0
) == -1) {
    perror("process_vm_writev");
    return 1;
}
free(tmp);
```

and now it works — we control the randomness!

[not-dev-random]: https://www.2uo.de/myths-about-urandom/
[@feedab1e]: https://github.com/feedab1e/

### Recording a session

We still need to record the TLS session so we can replay it. We *could* hook `read(2)` and `write(2)`,
but there’re quite a bit of syscalls that can read and write, so it’s easier to just point our
HTTP client to a TCP proxy. socat has everything we need:

```sh
socat \
    # Save traffic from client to server to `ltr`:
    -r ltr \
    # Save traffic from server to client to `ltr`:
    -R rtl \
    # Listen on port 44444:
    TCP-LISTEN:44444 \
    # And proxy everything to example.com:
    TCP:example.com:443
```

Now we can run curl, recording our session:

```sh
build/rwrapper curl --connect-to example.com:443:localhost:44444 https://example.com
```

and replay the session using socat:

```sh
socat -r ltr.new -R rtl.new TCP-LISTEN:44444 \
    # New: replay whatever server said last time.
    - < rtl > request
```

and run the same curl command again:

```console
$ build/rwrapper curl --connect-to example.com:443:localhost:44444 https://example.com
curl: (35) OpenSSL/3.0.14: error:0A0003E7:SSL routines::invalid session id
```

...it was never going to be easy, was it?


### Hunting for nondeterminism

There’re quite a few things that can go wrong here.

One thing I mentioned before is time: I have no idea how TLS looks, but a lot of protocols use
the current time somewhere, so maybe that’s the issue. I’ve made a list of all the syscalls curl
uses and there was nothing time-related, but there was `clone3`: a syscall that spawns another
process or thread. Multithreading is very bad for us: we only trace a single thread,
and scheduling introduces an additional source of nondeterminism besides.
I didn’t find how to disable multithreading in curl, so I switched to wget.

wget didn’t spawn any new threads, nor did it query the current time, but the problem persisted.
I started thinking about OpenSSL and randomness and remembered a writeup of the [Debian weak keys]
disaster:

> The broken version of OpenSSL was being seeded only by process ID.
> Due to differences between endianness and sizeof(long), the output was architecture-specific:
> little-endian 32bit (e.g. i386), little-endian 64bit (e.g. amd64, ia64),
> big-endian 32bit (e.g. powerpc, sparc). PID 0 is the kernel and PID_MAX (32768)
> is not reached when wrapping, so there were 32767 possible random number streams per architecture.
> This is (2^15-1)*3 or 98301. 
>
> *(from [Debian Wiki])*

Sure, they fixed the vulnerability, but the random generator in OpenSSL is probably still seeded
with the process ID (and possibly other unrelated stuff).

We could hunt down all the data OpenSSL uses to seed its CSPRNG, or (and this is probably the best option)
we could run the client in a more deterministic environment, but I didn’t want to spend too much time
on the proof of concept, so I decided to just write a simple HTTP client that uses rustls instead.
Sure, it reduces portability, but our code is not actually tied to any specific HTTP client, so
we could try running real curl again later.

I wrote a basic HTTP client to test it, reproduced here in its entirety:

```rust
use std::{env, io::Write};

fn main() {
    let url = env::args().nth(1).expect("didn't get an url");
    let body = ureq::get(&url)
        .call()
        .expect("failed to make a request")
        .into_string()
        .expect("failed to read body");
    std::io::stdout()
        .lock()
        .write_all(body.as_bytes())
        .expect("failed to write body to stdout");
}
```

It doesn’t support `--connect-to` though (and wget actually doesn’t support it either;
I did the next part earlier, but moved it down for storytelling reasons), so we need
to be able to redirect connections to our proxy.

[Debian weak keys]: https://16years.secvuln.info/
[Debian Wiki]: https://wiki.debian.org/SSLkeys

### Patching `connect(2)`

The plan is simple: whenever our client tries to connect to the server
we overwrite the address with `127.0.0.1:44444`.
That won’t work for IPv6, but extending it to IPv6 is trivial, so we won’t bother.

`connect(2)` looks like this:

```c
int connect(int sockfd, const struct sockaddr *addr, socken_t addrlen);
```

The interesting part is `addr`: we can read it to check if it looks like a HTTPS
connection and then overwrite it with a new address.
All these things need to happen on syscall entry, before the kernel can read the address.

```c
if (strcmp(last_syscall, "connect") == 0) {
    // First we want to read the address:
    struct sockaddr host;
    struct iovec local = { &host, sizeof(struct sockaddr) };
    struct iovec remote = { (void*) last_args[1], sizeof(struct sockaddr) };
    //                      ^ addr is the second argument
    if (process_vm_readv(
        /* pid = */ child,
        /* local_iov = */ &local, /* liovcnt = */ 1,
        /* remote_iov = */ &remote, /* riovcnt = */ 1,
        /* flags = */ 0
    ) == -1) {
        perror("process_vm_readv");
        return 1;
    }
    // HTTP client can do DNS requests.
    // `is_dns()` is a tiny function that returns `true`
    // if port is either 53 (DNS) or 853 (DNS-over-TLS).
    if (host.sa_family == AF_INET && !is_dns((struct sockaddr_in*) &host)) {
        ((struct sockaddr_in*) &host)->sin_addr.s_addr = htonl(0x7F000001);
        //                                                     ^ 127.0.0.1
        ((struct sockaddr_in*) &host)->sin_port = htons(44444);
        if (process_vm_writev(
            /* pid = */ child,
            /* local_iov = */ &local, /* liovcnt = */ 1,
            /* remote_iov = */ &remote, /* riovcnt = */ 1,
            /* flags = */ 0
        ) == -1) {
            perror("process_vm_writev");
            return 1;
        }
    }
}
```

With this ready we can use the same socat trick to check it:

```console
$ build/rwrapper build/requester 'https://example.com'
cut: all the contents of example.com
```

Wow it actually worked. Just to be sure, let’s check that sessions are the same:

```console
$ cmp ltr ltr.new; echo $?
0
$ cmp rtl rtl.new; echo $?
0
```

oh my god it works

### Wrapping up

Using our wrapper we can easily implement a simple signing fetcher:

```sh
# trurl is awesome!
# No more parsing URLs with regexes.
host="$(trurl --get '{host}' "$url")"
port="$(trurl --get '{port}' "$url")"
port="${port:-443}"
# 53 and 853 are used for DNS, so our wrapper won't redirect them.
if [ "${port}" = 53 ] || [ "${port}" = 853 ]; then
    printf 'Ports 53 and 853 are not supported.\n' >&2
    exit 1
fi
 
# Seed our RNG and save the seed.
# (random_seed is a little program that just generates a random number)
RWRAPPER_SEED="$(build/random_seed)"
printf "%llu" "$RWRAPPER_SEED" > "${data_dir}/seed"
export RWRAPPER_SEED

# Run `socat` in background:
socat -r "${data_dir}/ltr" -R "${data_dir}/rtl" TCP-LISTEN:44444 "TCP:${host}:${port}" &

# Do the request:
build/rwrapper build/requester "$url" > "${data_dir}/data"

# And wait for socat to exit:
wait
```

Now we have a signed page in `${data_dir}/data`.
To verify it we just replay the session:

```sh
RWRAPPER_SEED="$(cat "${data_dir}/seed")"
export RWRAPPER_SEED

# Save new ltr + rtl files:
socat -r "${work_dir}/ltr" -R "${work_dir}/rtl" \
    # And replay the old RTL file for the client:
    TCP-LISTEN:44444 - < "${data_dir}/rtl" > "${work_dir}/received" &

# Requester may panic if signature verification failed:
if ! build/rwrapper build/requester "$url" > "${work_dir}/data"; then
    printf 'Verification failed: requester returned non-zero.\n' >&2
    exit 1
fi

# If it didn’t, we check that it produced the same data:
if ! cmp "${data_dir}/data" "${work_dir}/data"; then
    printf 'Verification failed: data files differ.\n' >&2
    exit 1
fi

# And that requester sent the same data:
if ! cmp "${data_dir}/ltr" "${work_dir}/ltr"; then
    printf 'Verification failed: request files differ.\n' >&2
    exit 1
fi

# Otherwise we’re done!
printf 'Verification success!\n'
```

### Results and future work

Once again, the code is available at [GoldsteinE/tlsign].

- We successfully signed a webpage with its TLS session! Yay!

- The process is quite fragile and would benefit from added isolation.
  Both HTTP clients should start in a quiet, empty namespace where nothing ever changes.
  Doing this will probably fix OpenSSL, so we can run curl instead of a custom requester.

- With our current implementation, HTTP client does a real DNS request on verification.
  This prevents offline validation and also completely breaks everything if IP ever changes,
  or maybe even if there’re multiple IPs.
  A real implementation should stub DNS resolving so it’s not an issue.

- I’m very much not a security expert. One of my concerns is that it may be possible to replace
  a signed file with another signed file from the same domain.
  I don’t think it *is* possible, and I didn’t manage to produce this issue, but I am not
  completely sure and any comments are welcome.

  One point against the validity of my implementation is the existence of the [Signed HTTP Exchanges] spec.
  Some smart people presumably considered this and found it to not be enough, so what’s the issue?
  The spec mentions shorter signature lifespans as one of the motivations, but I don’t think
  it’s relevant for e.g. the original case of generating previews.

  One possible hardening measure here is to prevent the attacker from tinkering with seeds:
  if, for example, we say that the seed is always hash of the URL, it would be harder to somehow mix
  different sessions into a one fake frankensession.

- I think that this approach may be worthwhile for the original problem (federating cached previews)
  with a bit of polishing.

- It felt like crimes and I had a lot of fun doing this.
