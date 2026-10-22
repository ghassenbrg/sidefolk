import { lazy, Suspense, useEffect, useState } from "react";
import type { Props } from "./Pet3D";
import { PetIllustration } from "./PetIllustration";
const SculptedPet = lazy(() => import("./Pet3D"));
export default function Pet(props: Props) {
  const [happy, setHappy] = useState(false);
  useEffect(() => {
    if (!happy) return;
    const timer = setTimeout(() => setHappy(false), 1600);
    return () => clearTimeout(timer);
  }, [happy]);
  if (props.style === "2d")
    return (
      <button
        className={`pet-canvas pet-2d ${happy ? "is-happy" : ""} mood-${props.mood}`}
        aria-label={`Pet your ${props.species || "bunny"} companion`}
        onClick={() => {
          setHappy(true);
          props.onPet?.();
        }}
      >
        <PetIllustration
          species={props.species || "bunny"}
          color={props.color}
          accessory={props.accessory}
          happy={happy}
          sleeping={props.mood === "sleeping"}
        />
        {happy && <span className="pet-heart">♥</span>}
      </button>
    );
  return (
    <Suspense
      fallback={
        <div className="pet-canvas">
          <PetIllustration
            species={props.species || "bunny"}
            color={props.color}
            accessory={props.accessory}
          />
        </div>
      }
    >
      <SculptedPet {...props} />
    </Suspense>
  );
}
