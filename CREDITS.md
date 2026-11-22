# Credits

What Schevana takes from others, and under which terms.

## Boids and Boids 3D

Boids (`apps/boids.ss`) is ported from Eduardo Cavazos's
[Boids in Niva](https://github.com/dharmatech/boids-niva) (MIT). Its two
blocker rules, clear view and back off, follow Gary William Flake's *The
Computational Beauty of Nature* (MIT Press, 1998), written from his
description. Boids 3D (`apps/boids3d.ss`) takes the same rules into three
dimensions, as Craig Reynolds' "Flocks, Herds, and Schools: A Distributed
Behavioral Model" (SIGGRAPH 1987) first had them.

## Springies

Springies (`apps/springies.ss`) is ported from Eduardo Cavazos's
Springies in [Agave](https://github.com/dharmatech/agave) (Apache 2.0),
which followed Douglas DeCarlo's XSpringies. Its physics is written
from XSpringies' behavior, not its (GPL) source, and its models are
made in code, not read from XSpringies' example files.

## The CADR's 5X5 font

The CADR's 5X5 font in `schevana/styles/genera.sls` (the glyphs of `genera-5x5`) is
MIT's, decoded from System 99's `fonts/5x5.qfasl`, under this license:

Copyright (c) 1980, Massachusetts Institute of Technology. All rights
reserved. Redistribution and use in source and binary forms, with or
without modification, are permitted provided that the following
conditions are met: Redistributions of source code must retain the above
copyright notice, this list of conditions and the following disclaimer.
Redistributions in binary form must reproduce the above copyright
notice, this list of conditions and the following disclaimer in the
documentation and/or other materials provided with the distribution.
Neither the names of the Massachusetts Institute of Technology nor the
names of its contributors may be used to endorse or promote products
derived from this software without specific prior written permission.
THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS
IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR
CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

## OPEN LOOK

The OPEN LOOK style's glyphs in `schevana/styles/open-look.sls` are Sun's glyph
fonts, `olgl10/12/14/19.bdf` from the X11R6 contrib tape, under their
notice:

Copyright 1989 by Sun Microsystems, Inc. Mountain View, CA. Permission
to use, copy, modify, and distribute this software and its documentation
for any purpose and without fee is hereby granted, provided that the
above copyright notices appear in all copies and that both those
copyright notices and this permission notice appear in supporting
documentation, and that the name of Sun Microsystems not be used in
advertising or publicity pertaining to distribution of the software
without specific, written prior permission. Sun Microsystems make no
representations about the suitability of this software for any purpose.
It is provided "as is" without express or implied warranty. SUN
MICROSYSTEMS DISCLAIM ALL WARRANTIES WITH REGARD TO THIS SOFTWARE,
INCLUDING ALL IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS, IN NO
EVENT SHALL SUN MICROSYSTEMS BE LIABLE FOR ANY SPECIAL, INDIRECT OR
CONSEQUENTIAL DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM LOSS OF
USE, DATA OR PROFITS, WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR
OTHER TORTIOUS ACTION, ARISING OUT OF OR IN CONNECTION WITH THE USE OR
PERFORMANCE OF THIS SOFTWARE.

Its shades and frame in `schevana/styles/open-look.sls` are translated from OLGX
and olwm (XView 3.2), whose notice asks for these words:

(c) Copyright 1989, 1990, 1991 Sun Microsystems, Inc. Sun design patents
pending in the U.S. and foreign countries. OPEN LOOK is a trademark of
USL. Used by written permission of the owners.

(c) Copyright Bigelow & Holmes 1986, 1985. Lucida is a registered
trademark of Bigelow & Holmes. Permission to use the Lucida trademark is
hereby granted only in association with the images and fonts described
in this file.

## Adwaita

The Adwaita style (`schevana/styles/adwaita.sls`) and its palettes
(`schevana/palettes/adwaita.sls`, `adwaita-dark.sls`) take facts alone
from GNOME's stylesheets: libadwaita 1.7.6's `src/stylesheet/` (LGPL-2.1+)
and GNOME Shell 48.7's `data/theme/gnome-shell-sass/` (GPL-2.0+). What was
taken: sizes, paddings, radii, colors and the alphas of the tints, the
fourteen avatar colors, the OKLab rule for the standalone colors, the
spinner's widths and speed, and how the Shell's panel, menus, dash and
banners are laid out, each cited in the code as file:line at those tags.
No SCSS, code, icon, image or font was copied: the glyphs (the check, the
window buttons' crosses, the dropdown's arrow, the spinner) are drawn from
their geometry, and the wallpaper is circles over GNOME's fallback blues,
not GNOME's image. Its text is Cantarell, which Debian sets for GNOME 48;
the OKLab conversion is Björn Ottosson's published one.
