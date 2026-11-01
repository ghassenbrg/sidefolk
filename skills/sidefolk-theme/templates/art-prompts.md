# Art prompts for a Sidefolk theme

Fill the `<…>`. Write the **style sentence once** and paste it word for word into every brief, so the set matches.
Make the light page wash first, look at it, then pass it as the reference for the dark one (same composition).
The nook backdrop is usually a crop of the page wash (`fit-art.py --crop`), which costs no image and matches.

**Style sentence:**

> Style: <medium: soft watercolour on paper / a gentle gouache landscape / a hazy photograph, slightly blurred> in
> <three to five colours named after the theme's tokens: e.g. muted matcha greens, warm pale hinoki wood, cream
> paper>; gentle diffuse light, very low contrast, calm and airy; no people, no text, no letters, no logos, no
> signatures or seals, no frames or borders.

Never name a brand, a game, a film, a studio or an artist; describe the look in plain words instead.

## Page wash, light (`art/page.png`, fitted to 1600 × 533)

> A very wide panoramic background banner, about 3:1 (landscape), for the top of an app page: cards and text sit
> over it, so it must be quiet. <The scene: what is there, where the light comes from>. The interest is in the top
> half and toward one side (<top right>); the lower third is almost plain <page colour in words> so it can fade
> into the page colour <surfaceSunken light, #RRGGBB>. Mostly <two pale colours>, nothing dark, no strong focal
> point, nothing in the centre, no hard line along the top edge. <style sentence>

## Page wash, dark (`art/page-dark.png`), with `--ref page-raw.png`

> The attached image is the daytime version of a very wide (about 3:1) page background for an app. Paint its night
> version with the same composition and the same width-to-height ratio: <the same scene at night, lit by what>.
> Very dark and very low contrast overall, <dark tones> close to <surfaceSunken dark, #RRGGBB>; the lower third
> almost plain and as dark as <#RRGGBB> so it fades into the page. No bright spots, nothing warm<, no moon or lamp:
> the companion's light is the only warm thing on screen>. <style sentence without "gentle diffuse light">

## Gallery picture (`art/tile.png`, fitted to 640 × 400), only for a gallery theme

> A landscape 16:10 picture card for a theme gallery, standing for a calm theme called <Name>. <A small scene that
> sums the concept up, one quiet object as a focal point in a lower third>. Plenty of calm empty space.
> <style sentence>

## Empty-page art (`art/empty.png`, 240 × 240), optional

> A small square spot illustration on a fully transparent background, for an empty page of an app: <one object
> from the concept: an empty tea bowl, a folded paper boat>, centred, with room around it, soft and friendly,
> <style colours>; no ground shadow, no background, no text.

Check the corners are transparent (`python3 -c "from PIL import Image; print(Image.open('art/empty.png').getpixel((0,0)))"`):
a generated "transparent" background is often a painted checkerboard. Skip empty art rather than ship a box.

## Grain (`art/grain.png`, 256 × 256): draw it, don't generate it

A seamless tile can't come from an image model. Draw noise plus a few hundred short fibres in Pillow, wrapping at the
edges (draw on a 3 × 3 canvas and keep the middle), grey around 210/255; the app multiplies it at 6%.

## Fitting

```sh
F=<skill>/templates/fit-art.py
python3 $F page-raw.png      <theme>/art/page.png      --size 1600x533 --fade-top 80 --page "<surfaceSunken light>" --colors 256
python3 $F page-dark-raw.png <theme>/art/page-dark.png --size 1600x533 --fade-top 80 --page "<surfaceSunken dark>" [--tint 0.82,0.78,0.68] --colors 256
python3 $F page-raw.png      <theme>/art/nook.png      --size 640x228 --crop <x0,y0,x1,y1 of a calm corner> --colors 256
python3 $F page-dark-raw.png <theme>/art/nook-dark.png --size 640x228 --crop <same box> --colors 256
python3 $F tile-raw.png      <theme>/art/tile.png      --size 640x400 --colors 256
```

`--tint` pulls a night picture off the blue cast image models give it, toward the theme's darks (measure the raw
picture's plain bottom band against `surfaceSunken`). Keep raw generations outside the theme folder: the gallery packs
every `art/*.png`.
