// Expressions from the character sheets, as face settings. Everything not named takes NEUTRAL.
// lid: top eyelid (0 open … 1 shut); lidSlant: + lowers the inner corner (cross), − the outer (sad);
// lidBottom: cheeks pushing up under a smile; happyEyes: shut eyes arch like ^ (1) or rest like ‿ (0).
export const NEUTRAL = {
  eyeOpen: 1, lid: 0, lidSlant: 0, lidBottom: 0, lidBottomSlant: 0, happyEyes: 0.5, giddy: 0,
  winkL: 0, winkR: 0, brow: 0, browAngle: 0, browRaise: 0,
  mouthOpen: 0, smile: 0.35, mouthWidth: 0.32, mouthRound: 0, cat: 0, wavy: 0, mouthX: 0,
  blush: 0.6, shy: 0, tears: 0, dizzy: 0, sparkle: 0.15, noseTwitch: 0,
};

export const MOODS = {
  neutral: {},
  smile: { smile: 0.85, mouthWidth: 0.45, blush: 0.75, lidBottom: 0.12 },
  happy: { mouthOpen: 0.45, smile: 0.95, mouthWidth: 0.6, blush: 0.85, lidBottom: 0.16, sparkle: 0.5 },
  excited: { eyeOpen: 1.12, mouthOpen: 0.6, smile: 1, mouthWidth: 0.72, blush: 0.95, sparkle: 1 },
  laugh: { lid: 1, happyEyes: 1, mouthOpen: 0.78, smile: 1, mouthWidth: 0.78, blush: 1.05 },
  giggle: { lid: 1, happyEyes: 1, mouthOpen: 0.38, smile: 1, mouthWidth: 0.5, blush: 1.15 },
  content: { lid: 1, happyEyes: 1, smile: 0.75, mouthWidth: 0.4, blush: 0.85 },
  wink: { winkL: 1, happyEyes: 1, mouthOpen: 0.35, smile: 1, mouthWidth: 0.55, blush: 0.9, sparkle: 0.8 },
  love: { lid: 1, happyEyes: 1, smile: 0.9, mouthOpen: 0.28, mouthWidth: 0.5, blush: 1.45, shy: 0.5 },
  curious: { eyeOpen: 1.08, mouthOpen: 0.14, mouthRound: 1, mouthWidth: 0.2, smile: 0, browRaise: 0.4, sparkle: 0.4 },
  attentive: { eyeOpen: 1.07, smile: 0.5, mouthWidth: 0.35, sparkle: 0.45 },
  thinking: { lid: 0.22, lidSlant: -0.15, smile: -0.05, wavy: 0.5, mouthX: 0.35, mouthWidth: 0.25, brow: 0.5, browAngle: -0.12, browRaise: 0.5 },
  focused: { lid: 0.14, smile: 0.3, mouthWidth: 0.22, cat: 1, sparkle: 0.3 },
  confused: { browAngle: 0.25, brow: 0.55, wavy: 1, mouthX: 0.4, mouthWidth: 0.3, smile: 0 },
  surprised: { eyeOpen: 1.22, mouthOpen: 0.55, mouthRound: 1, mouthWidth: 0.35, brow: 0.55, browRaise: 1, browAngle: -0.1 },
  shocked: { eyeOpen: 1.3, mouthOpen: 0.85, mouthRound: 1, mouthWidth: 0.4, brow: 0.7, browRaise: 1.2 },
  shy: { lid: 0.12, lidBottom: 0.22, smile: 0.55, mouthWidth: 0.2, blush: 1.55, shy: 1 },
  sleepy: { lid: 0.55, happyEyes: 0.2, smile: 0.2, mouthWidth: 0.2, blush: 0.6 },
  asleep: { lid: 1, happyEyes: 0.15, mouthOpen: 0.07, mouthRound: 1, mouthWidth: 0.12, smile: 0.1, blush: 0.65 },
  yawn: { lid: 1, happyEyes: 0.1, mouthOpen: 1, mouthRound: 1, mouthWidth: 0.55, smile: 0 },
  sad: { lid: 0.3, lidSlant: -0.55, smile: -0.75, mouthWidth: 0.3, brow: 0.85, browAngle: -0.38, blush: 0.5 },
  cry: { lid: 0.35, lidSlant: -0.6, smile: -0.8, mouthOpen: 0.25, mouthWidth: 0.35, brow: 0.9, browAngle: -0.4, tears: 1 },
  angry: { lid: 0.3, lidSlant: 0.75, brow: 1, browAngle: 0.48, smile: -0.6, mouthOpen: 0.14, mouthWidth: 0.35, blush: 0.95 },
  pout: { smile: -0.4, mouthWidth: 0.14, lid: 0.12, lidSlant: 0.25, blush: 0.95, brow: 0.4, browAngle: 0.2 },
  determined: { lid: 0.2, lidSlant: 0.4, brow: 0.8, browAngle: 0.35, smile: 0.3, mouthWidth: 0.3, sparkle: 0.6 },
  dizzy: { dizzy: 1, lid: 1, wavy: 1, smile: 0, mouthWidth: 0.35 },
  wince: { lid: 1, giddy: 1, smile: -0.3, wavy: 0.7, mouthWidth: 0.4 },
  oops: { smile: 0.4, wavy: 0.8, lidBottom: 0.15, blush: 1.05, brow: 0.6, browAngle: -0.3 },
};

export function moodFace(name) {
  return { ...NEUTRAL, ...(MOODS[name] || {}) };
}
