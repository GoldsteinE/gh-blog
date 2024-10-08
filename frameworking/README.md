# Some thoughts on Framework 16

I’ve recently changed my laptop from a trusty ThinkPad P1 Gen 3, which kinda fell apart completely in 3ish years,
once again proving that ThinkPads are not what they once were, to a Framework 16. This migration had some good sides
and some bad sides. Overall I’m pretty happy with it, but here’s some specific stuff I noticed.

* **The display**: it’s not 4K. Why isn’t it 4K.

  See, other than than it’s a pretty nice display: I like the colors, it has a high refresh rate
  (although it’s kinda fake given that up+down time is 9ms), and it can be really bright.
  But 2560x1600 is really, really not enough for a 16" display. Fonts are just blurry. I got used
  to it after some time, but on small font sizes it still looks horrible. I hope they’ll make a 4K
  display module someday.

  A related problem is fractional scaling. This resolution calls for, like, 1.5 scale, but Linux can’t do it.
  You’ll see news like “wl-roots can into fractional scaling” and “Firefox can into fractional scaling”,
  but [no it can’t][sway] and [no it can’t][firefox]. Your best bet is to scale 2x and use features like Firefox’s
  `devPixelsPerPx` or just font sizes to scale it back down somewhat.

  [sway]: https://github.com/swaywm/sway/issues/8117
  [firefox]: https://bugzilla.mozilla.org/show_bug.cgi?id=1849109

* **The coolers**: they’re fucking loud.

  [fw-fanctrl] helps somewhat (although you can’t use it with Secure Boot because of its somewhat
  cursed implementation), but overall it’s just a problem of “CPU heats a lot, so it needs a lot
  of cooling”. This heat also makes the bottom panel quite hot, but I’m not really bothered by this.

  [fw-fanctrl]: https://github.com/TamtamHero/fw-fanctrl/

* **The keyboard**: I love it actually. It has nice 1.5mm key travel, which is enough to make it nicely
  tactile. Objectively speaking, I can get to ~110 wpm on my Framework, which is near the max I can do.
  I got a blank one, because I love the aesthetics, and installed the RGB macropad alongside it.
  Keys on the macropad are somewhat worse, you can feel them bending if you press hard enough, and they’re
  not really even, but I don’t type on it for extended periods of time, so whatever. Everything is QMK,
  so that’s fun.

* **The fingerprint reader**: it actually works every time. That wasn’t the case on my ThinkPad.

* **Performance**: it’s quite fast, I really like how rust-analyzer initialization got much
  faster compared to my old laptop.

* **The form-factor**: it’s rather heavy, especially with GPU attached, and when it’s sitting on my lap,
  the edge that presses on my knee is quite sharp. Ethernet port is huge, so it’s not really viable to
  have it installed all the time.

* **The build quality**: a lot of stuff is wonky. Trackpad and trackpad spacers are not fixed in place
  properly. They also don’t really line up with the rest of the laptop. Macropad was also jiggly, but
  I fixed that by just adding a little paper “spacer” inside (it’s not visible from the outside). 
  
  Trackpad spacer problem could be solved by [3D-printing custom spacers][spacers], but you need to
  print them out of something that can resist high temperatures, because otherwise it just gets deformed
  and the problem reappears.

  [spacers]: https://www.printables.com/model/804797-framework-laptop-16-trackpad-spacer

* **The battery life**: I have kind of a low bar here, but 85W is enough for me. It’s actually a bit
  higher than advertised: right now my battery indicator shows 106.52% charge. I think you can use it
  for quite a long time with proper power-saving mode, but I haven’t gotten around to configuring that.
  Even with not-power-saving-at-all setup it still saves me from thinking about the charger all the time.

* **The speakers**: they’re okay. It’s not MacBook, but it’s not awful. Linux compatibility mode in UEFI +
  [easyeffects setup from Arch Wiki][easyeffects] makes it a lot better.

  [easyeffects]: https://wiki.archlinux.org/title/Framework_Laptop_16#Easy_Effects

* **The WiFi module**: it’s slower than my old one for some reason. Maybe it’s something with misconfigured
  regulatory domains? I have a pretty weak router, so that can also be a factor. It’s still fast enough that
  I don’t really care.

* **The gimmick**: yeah, you can swap ports, that’s pretty fun. The best part is I can actually have USB A
  ports, which seem to be considered deprecated by, like, every other manufacturer. You can pry my USB A
  Yubikey from my cold dead hands.
