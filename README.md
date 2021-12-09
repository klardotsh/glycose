# glycose: sugar over the gly format

This repo implements a few helpers around the [Gly inline graphics
format](https://wiki.xxiivv.com/site/gly_format.html) seen in some Hundred
Rabbits projects. You'll need a Zig 0.8+ compiler to run this stuff.

- `gly2pbm` converts a series of Gly bytes into [Portable
  BitMap](https://en.wikipedia.org/wiki/Netpbm) data. Currently, only `P1`
  (uncompressed ASCII) is generated (PBM can optionally be encoded into a
  binary `P4` format, for example by ImageMagick). It has no command line
  arguments, or indeed any configurability at all. Pipe valid Gly data into
  stdin, out comes P1-encoded PBM text on stdout.

```sh
$ zig build -Drelease-safe

# copy zig-out/bin/gly2pbm anywhere in your $PATH, perhaps ~/bin (if
# applicable) or /usr/local/bin

# boxgly.gly is a binary blob based on the drawing at
# https://wiki.xxiivv.com/site/gly_format.html provided for your convenience
$ gly2pbm < boxgly.gly > boxgly.pbm

# now you can use imagemagick to make it back into a PNG, perhaps:
$ convert boxgly.pbm boxgly_after_glycose.png

# there's no diff between devine's reference image and our generated
$ compare -verbose -metric AE '(' boxgly.png -colorspace gray ')' '(' boxgly_after_glycose.png -colorspace gray ')' boxgly_diff.png
# > boxgly.png PNG 32x32 32x32+0+0 8-bit sRGB 698B 0.000u 0:00.000
# > boxgly_after_glycose.png PNG 32x32 32x32+0+0 8-bit Gray 2c 325B 0.000u 0:00.000
# > Image: boxgly.png
# >   Channel distortion: AE
# >     gray: 0
# >     alpha: 0
# >     all: 0
# > boxgly.png=>boxgly_diff.png PNG 32x32 8-bit Gray 698B 0.000u 0:00.000

# what if you have a very high DPI monitor and 32x32 bitmaps are unreadable? #
# https://github.com/visioncortex/vtracer CLI to the rescue. with these
# arguments, the output will still look like a bunch of square pixels, just
# cleanly zoomed. think like a bitmap font that was pixel-doubled to @2x scale
$ vtracer --input boxgly.pbm --output boxgly.svg --preset bw -m pixel -f 1
```

## Boring Legal Bullshit

The `boxgly.png` image refered to in the unit tests, its binary representation
in `boxgly.gly` used as an example, as well as the Gly format description
itself, are, as far as I can tell, licensed [CC BY-NC-SA
4.0](https://creativecommons.org/licenses/by-nc-sa/4.0/) upstream. As for my
own code (everything else in this repository):

> Released by klardotsh under your choice of the Guthrie Public License
> (https://web.archive.org/web/20180407192134/https://witches.town/@ThatVeryQuinn/3540091)
> or CC0-1.0 (https://creativecommons.org/publicdomain/zero/1.0/)
> 
> Anybody caught forkin it without our permission, will be mighty good friends
> of ourn, cause we don't give a dern. Publish it. Write it. Fork it. Push to
> it. Yodel it. We wrote it, that's all we wanted to do.
