# Making your own pet model

Sidefolk can wear any model that follows its rig contract. In the Sidefolk window open
**Crew**, pick a companion, then **Appearance → Other ways to choose a look → Import a model…**
and pick a `.glb` file. The model is copied into Sidefolk's data folder (`models/`) and shows up
under **Character** for every companion.

If the model does not fit, the pet keeps its current body and says what is missing.

## The contract

The same contract all eighteen built-in bodies follow
(`art/blender/build_hero.py` builds them; read it as a worked example). A character without
ears or arms keeps those bones and simply has no geometry on them: the capsule's alert sign
rides its hidden right arm bone.

**File:** binary glTF (`.glb`), at most 20 MB. Feet at y = 0, about 2.5 units tall, facing +z.

**Meshes:** two skinned meshes on one skeleton.

- `Body`: everything that gets the dark outline.
- `Face`: small details on top (eyes, mouth, inner ears). It gets no outline and is ignored
  for clicks.

**Bones** (exact names): `root`, `hips`, `chest`, `head`, `earL`, `earLTip`, `earR`, `earRTip`,
`eyeL`, `eyeR`, `armL`, `armR`, `legL`, `legR`, `tail`. Give them identity rest rotations
(bones pointing straight up with no roll), so the app's gaze and blinking act on the axes it
expects. The app scales the eye bones vertically to blink, so weight eye geometry to them
alone.

**Clips** (exact names, each keying every bone): `idle`, `walk`, `sit`, `sleep`, `wave`,
`think`, `read`, `work`, `celebrate`, `alert`, `sad`, `dangle`, `fall`. `alert` should raise the
right arm: the app puts a "!" sign in the right paw.

**Colors:** vertex colors (`COLOR_0`) with a toon material look best. Palettes recolor these
exact colors (linear RGB), so use them where you want palettes to apply:

| Region | Linear RGB |
|---|---|
| Coat | 0.88, 0.776, 0.644 |
| Points (ear tips, paws, feet) | 0.068, 0.05, 0.078 |
| Scarf | 0.159, 0.624, 0.456 |
| Scarf detail | 0.105, 0.479, 0.342 |
| Muzzle and belly | 1, 0.956, 0.896 |

Other colors are left alone.

Accessories attach to the `head` bone at fixed spots fitted for the built-in heads; on a very
different head they may float.

**Budget:** under 8,000 triangles and 2 MB per pet, no textures needed (vertex colors carry the
palette regions). Every art style (Soft 3D, Ink & Geek, Pocket Anime) is drawn from the same
model by the app, so one file covers all three.
