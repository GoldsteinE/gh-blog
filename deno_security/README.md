# I’m not a fan of Deno’s security model

This has been bothering me for a while now, so I want to write down my thoughts
so I can get it out of my head and move on. We’re gonna talk about how Deno approaches
security, specifically with its permissions system, and why I think this approach
is fundamentally insecure and misleading.

## Wait, what’s Deno?

[Deno] is a language runtime for JavaScript. It consists of a standard library, a package manager,
a TypeScript transpiler and a bunch of other stuff that’s not important for our story. It’s not
a JavaScript _implementation_, so it does not interpret or compile JavaScript, it reuses V8 for that.

One of the flagship features of Deno is its permission system (it’s under the “Secure by default”
header on their [landing page][Deno]). The idea is simple: as JS code running in Deno needs the
standard library to access the outside world, Deno can choose which accesses it allows or disallows,
so when you run

```shell
deno run --allow-read=/tmp/dir --allow-run=uname code.ts
```

the standard library will only allow `code.ts` to read `/tmp/dir` and run `uname`.

Additionally, a program can request permissions at runtime, so code like

```typescript
const r = { name: "read", path: "/tmp/dir" } as const;
await Deno.permissions.request(r);
```

will display a nice little prompt in the terminal:

```
┌ ⚠️  Deno requests read access to "/tmp/dir".
├ Requested by `Deno.permissions.request()` API.
├ Run again with --allow-read to bypass this prompt.
└ Allow? [y/n/A] (y = yes, allow; n = no, deny; A = allow all read permissions) > 
```

and you can grant or refuse it.

(Aside: I really miss this feature in browser extensions. Currently, if your extension needs _potential_
access to _any_ website, it needs to request _actual_ access to _all_ the websites, which is less than ideal)

If you like puzzles, this is the point where you can stop and think about what could go wrong with this system.

[Deno]: https://deno.com

## The prompts problem

Of the two specific issues I want to point out this is the less severe one. We’ll discuss it first
because this was the first thing I noticed and it kinda immediately irked me when I first read
about this.

(If you’re only interested in the more juicy part, you can skip to the [next section](#the---allow-run-problem)).

So, this nice little prompt is displayed in the terminal. It’s not, like, a PolKit GUI window or anything,
it’s just text on stdout waiting for input from stdin. This is a wild thing to do.

You see, terminal has a somewhat weird API. Most of the commands / requests application can send to the terminal
are sent in-band, by printing them to stdout. Terminal can then reply by sending data to stdin.
As Deno allows programs to print arbitrary data to stdout and read from stdin without requiring any permissions
or doing any filtering, malicious code can send arbitrary commands to the terminal. It’s usually okay,
because terminals won’t, like, execute shell commands just because stdout told them to, you’re supposed
to be able to freely `cat` files without risking arbitrary code execution. It’s markedly less okay if
you allow malicious code to do whatever with the terminal and then print a prompt on the same exact terminal.

You could, like, [hide the prompt by messing with terminal colors][#9666].

Or [trick the user into pre-feeding approval into stdin][#9750].

Or [trick the terminal into feeding approval into stdin as a response to some request][#9750-comment].
(Terminal won’t ever send Enter to stdin to avoid executing commands, but “press Enter to continue”
is common enough to not be suspicious; the user never sees the actual prompt):

[![asciicast](https://asciinema.org/a/9rvK8ANJK0WnQc9nsrFKdC7ir.svg)](https://asciinema.org/a/9rvK8ANJK0WnQc9nsrFKdC7ir)

The specific issue on the screencast is long patched; the issue with terminal colors is not.
That doesn’t really matter because the _real_ issue is using an attacker-controlled channel for
security-sensitive information. It’s like executing attacker-controlled JS code on a webpage
and then asking for password on the same page. You can’t know that the page is in a safe state,
so you can’t trust any input.

Even if Deno manages to patch every single issue with the “standard” escape codes, you never know
which non-standard codes even exist out there. Many terminals have some, it’s impossible to predict
how they will interact with your prompt.

(Aside: how come sudo can do it then? The difference is that sudo asks for the password first,
before running any other code. To trick sudo that way you’d need to fuck up terminal state before
you even type `sudo`, and do it quietly enough that you don’t notice it while you type it.
If some terminal allows it, I’d consider it a bug in the terminal)

[#9666]: https://github.com/denoland/deno/issues/9666
[#9750]: https://github.com/denoland/deno/issues/9750
[#9750-comment]: https://github.com/denoland/deno/issues/9750#issuecomment-796702901

## The `--allow-run` problem

So, there’s a weird thing with this command I wrote above (I’ll copy it here for reference):

```shell
deno run --allow-read=/tmp/dir --allow-run=uname code.ts
```

What does `--allow-run=uname` even mean? It’s not like programs have canonical names, it’s not `org.gnu.coreutils.uname`,
it’s not even `/nix/store/8k1dmzr3gwzqdgw45nzj76902ca7g1is-coreutils-full-9.5/bin/uname`. It’s just a shortcut for
“look at all the directories in `PATH` one-by-one to see if you can find `uname` there”.

You can set environment variables for the child process without needing any extra permissions, so what if we just

```
$ cat t.ts
const command = new Deno.Command("uname", {
  // my current working directory, can be anything
  env: { 'PATH': '/tmp/tmp.7ofmKaNW83' },
});
const { code, stdout, stderr } = command.outputSync();
console.log(new TextDecoder().decode(stdout));
$ cat uname
#!/bin/sh
printf lol
$ deno run --allow-run=uname t.ts
lol
```

yeah.

Once again, we have a pretty and convenient interface that doesn’t really make sense from the security standpoint.
It would be _nice_ if programs were uniquely identified by their names, but they’re _not_, and pretending they are
leads to security holes.

Funnily enough, I didn’t even think that this issue would be there when I poked at Deno for the first time,
so I haven’t reported it [until now][#11964-comment] (spoiler alert: this is a comment on a GitHub issue
that I created for the problem I’ll explain below).

So let’s imagine we fixed that. It’s not _that_ hard, we can force `PATH` to be whatever it was when the runtime started,
or always require fully-qualified paths, or prompt with a fully-qualified path before running. Are we safe now?

Lol no of course we’re not. While `PATH` decides which executable gets run, dynamically-linked executables (so, like, most executables)
require dynamic loader to actually start. Dynamic loader is a program that, well, loads the executable into memory, finds its
dependencies and does a bunch of other fun stuff we won’t get into. The important part is that dynamic loader is _configurable_
via environment variables. You can probably see where this is going now.

`LD_PRELOAD` instructs the dynamic loader to load specific dynamic library when loading executables.
Dynamic libraries can execute arbitrary code on load.
We can just pass `LD_PRELOAD` and we’ve completely escaped the sandbox once again:

```
$ cat t.c
#include <stdio.h>

// ask dynamic loader to run this function on load time pretty please
__attribute__((constructor)) void lol() {
    puts("lol");
}
$ cat t.ts
const command = new Deno.Command("uname", {
  // ask dynamic loader to load our evil library
  env: { 'LD_PRELOAD': '/tmp/tmp.7ofmKaNW83/liblol.so' },
});
const { code, stdout, stderr } = command.outputSync();
console.log(new TextDecoder().decode(stdout));
$ gcc -fPIC -shared t.c -o liblol.so
$ # that's the real uname now!
$ deno run --allow-run=uname t.ts
lol
Linux
```

I [reported this][#11964] some time ago and now they [patched it][#25271] by disallowing to set
environment variables starting with `LD_`. This, once again, fixes a specific issue while ignoring the larger
problem: “permission to run a single command” is mostly not a useful concept.
(You _can_ do secure interfaces by allowing to run a single command, like git-over-SSH does,
but generally both the environment and the command need to be prepared to handle it)

Say, for example, our script wants to invoke the `$EDITOR` so user can edit some data (think git commit messages). 
That’s a very natural permission request, and it’s also an unmitigated disaster because most editors are
configurable enough for running one to be a full sandbox escape. It’s easy for user to absent-mindedly
grant `--allow-run=vim` (“well, sure, I want to edit this file!”), but then the script can just set
`VIMINIT='!rm -rf /*'` and oops, all my files are gone. Most programs are configurable, often in some
ways you won’t think about (like `LD_PRELOAD`), and attacker controls the execution enviornment.
“Patch some specific ways to configure programs” is not the solution, the solution is to sandbox all the code,
not just JS code.

When we discussed all this stuff in GitHub issues, a Deno developer wrote:

> The main thing it protects you against is malicious code that isn't smart enough.

Upon reading this, I was enlightened.

[#11964]: https://github.com/denoland/deno/issues/11964
[#25271]: https://github.com/denoland/deno/pull/25271
[#11964-comment]: https://github.com/denoland/deno/issues/11964#issuecomment-2322993158

## Conclusions

Deno tries really hard to do what the operating system should be doing. It emulates syscall filtering by
filtering standard library calls. Unfortunately, this breaks down the second you need to run code
that doesn’t use Deno standard library. It also uses somewhat flawed approach to permission management
that _looks_ good (wow, runtime prompts! omg, I can just `--allow-run=uname`!), but introduces security
risks. In doing this, it implicitly requires user to understand all the implications of various permissions
and their combinations, which can be really hard.

Deno process is not actually sandboxed, it only pretends it is. I didn’t mention some more boring issues like
“Deno doesn’t prevent you from following symlinks that lead outside of the sandbox” because they all just boil
down to this simple one: the process is not sandboxed.

One can argue that this pseudo-sandboxing is better than nothing: after all, not all the malicious code is smart enough.
I disagree: Deno permissions give a false sense of security and can lure someone into running untrusted code without proper sandboxing.

It’s possible that you can use Deno sandboxing safely if you:

- never use more dangerous permissions like `--allow-run`, even with `=cmd`,
- that includes `--allow-env`, even `--allow-env=VAR`, for setting environment variables is memory unsafe and can affect libc functions,
- preferrably run with `--no-prompt` so your terminal can’t be tricked,
- are careful about symlinks in directories you `--allow-{read,write}` to,
- are not concerned with resource exhaustion: there’re zero permissions required to burn CPU or allocate memory.

In particular, you may be safe if you’re running untrusted code with no permissions at all
in a non-interactive context and use some other mechanism to control resource consumption.

I still don’t think you _should_ do it. This path is riddled with footguns because you’re
executing untrusted code in a fully-privileged process, and the moment you need _some_ OS interactions
you’re no longer running code “with no permissions at all”. You should not try to figure out which
stdlib APIs can lead to a sandbox escape when combined. You should just use a proper sandbox.

I’m not a fan of Deno’s security model.

## So what do we do?

Just `bwrap` untrusted shit.

Also, please: don’t harass Deno developers.
We have a technical disagreement, but no technical disagreement was ever solved by harassment.
This post is explicitly not an invitation to do it.
I’ve already explained my point of view to them, they disagreed, and that’s okay.
You don’t need to reiterate it, it won’t help anybody.
