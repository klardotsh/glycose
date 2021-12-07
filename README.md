# glycose: sugar over the gly format

This repo implements a few helpers around the [Gly inline graphics
format](https://wiki.xxiivv.com/site/gly_format.html) seen in some Hundred
Rabbits projects. You'll need a Zig 0.8+ compiler to run this stuff.

- `gly2pbm` converts a series of Gly bytes into [Portable
  BitMap](https://en.wikipedia.org/wiki/Netpbm) data. Currently, only `P1`
  (uncompressed ASCII) is generated (PBM can optionally be encoded into a
  binary `P4` format, for example by ImageMagick)

## Boring Legal Bullshit

The `boxgly.png` image refered to in the unit tests, as well as the Gly format
description itself, are, as far as I can tell, licensed [CC BY-NC-SA
4.0](https://creativecommons.org/licenses/by-nc-sa/4.0/) upstream. As for my
own code (everything else in this repository):

> Released by klardotsh under your choice of the Guthrie Public License
> (https://web.archive.org/web/20180407192134/https://witches.town/@ThatVeryQuinn/3540091)
> or CC0-1.0 (https://creativecommons.org/publicdomain/zero/1.0/)
> 
> Anybody caught forkin it without our permission, will be mighty good friends
> of ourn, cause we don't give a dern. Publish it. Write it. Fork it. Push to
> it. Yodel it. We wrote it, that's all we wanted to do.
