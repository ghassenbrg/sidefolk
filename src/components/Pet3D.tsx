import { petCatalog, type PetSpecies } from "../../shared/pets";
import { PetIllustration } from "./PetIllustration";
import {
  Component,
  useEffect,
  useMemo,
  useRef,
  useState,
  type ReactNode,
} from "react";
import { Canvas, useFrame, useThree } from "@react-three/fiber";
import * as THREE from "three";

const colors = { sage: "#a6b994", peach: "#e9b39e", lilac: "#b8afd0" };
export type Props = {
  accessory?: "none" | "glasses" | "headphones";
  species?: PetSpecies;
  style?: "2d" | "3d";
  color: keyof typeof colors;
  mood: "idle" | "working" | "reminder" | "sleeping";
  onPet?: () => void;
  floating?: boolean;
};
function Ticker() {
  const invalidate = useThree((s) => s.invalidate);
  useEffect(() => {
    const reduced = matchMedia("(prefers-reduced-motion: reduce)").matches;
    const id = setInterval(
      () => {
        if (!document.hidden) invalidate();
      },
      reduced ? 1000 : 1000 / 24,
    );
    return () => clearInterval(id);
  }, [invalidate]);
  return null;
}
function Creature({
  color,
  mood,
  onPet,
  species = "bunny",
  accessory = "none",
}: Props) {
  const group = useRef<THREE.Group>(null),
    eyes = useRef<THREE.Group>(null),
    leftArm = useRef<THREE.Mesh>(null),
    rightArm = useRef<THREE.Mesh>(null);
  const happyUntil = useRef(0);
  const elapsed = useRef(0);
  const reduced = useMemo(
    () => matchMedia("(prefers-reduced-motion: reduce)").matches,
    [],
  );
  const smile = useMemo(
    () =>
      new THREE.TubeGeometry(
        new THREE.CatmullRomCurve3([
          new THREE.Vector3(-0.13, 0.89, 0.773),
          new THREE.Vector3(0, 0.83, 0.79),
          new THREE.Vector3(0.13, 0.89, 0.773),
        ]),
        16,
        0.023,
        8,
        false,
      ),
    [],
  );
  useEffect(() => () => smile.dispose(), [smile]);
  useFrame(({ clock }) => {
    const t = clock.getElapsedTime();
    elapsed.current = t;
    if (!group.current || !eyes.current) return;
    const happy = t < happyUntil.current;
    group.current.position.y =
      -0.2 +
      (reduced ? 0 : Math.sin(t * (happy ? 7 : 2)) * (happy ? 0.11 : 0.045));
    group.current.rotation.y = reduced ? -0.12 : Math.sin(t * 0.6) * 0.11 - 0.1;
    group.current.rotation.z =
      mood === "sleeping"
        ? 0.12
        : mood === "working"
          ? Math.sin(t * 4) * 0.045
          : 0;
    const blink = Math.sin(t * 0.7) > 0.992;
    eyes.current.scale.y = mood === "sleeping" || blink ? 0.12 : 1;
    if (leftArm.current && rightArm.current) {
      leftArm.current.rotation.z =
        -0.3 + (happy || mood === "reminder" ? Math.sin(t * 8) * 0.35 : 0);
      rightArm.current.rotation.z =
        0.3 + (mood === "working" ? Math.sin(t * 6) * 0.25 : 0);
    }
  });
  const coat =
    species === "bunny"
      ? colors[color]
      : petCatalog.find((p) => p.id === species)!.color;
  const earScale: [number, number, number] =
    species === "bunny"
      ? [0.24, 0.5, 0.23]
      : species === "frog"
        ? [0.3, 0.25, 0.23]
        : species === "ghost"
          ? [0.01, 0.01, 0.01]
          : [0.3, 0.3, 0.23];
  const sphere = (
    position: [number, number, number],
    scale: [number, number, number],
    material: string,
    key: string,
  ) =>
    species === "ghost" && /^(ear|inner|foot|belly|muzzle)/.test(key) ? null : (
      <mesh key={key} position={position} scale={scale} castShadow>
        {key.startsWith("ear-") && (species === "cat" || species === "fox") ? (
          <coneGeometry args={[1, 2, 3]} />
        ) : (
          <sphereGeometry args={[1, 32, 24]} />
        )}
        <meshStandardMaterial color={material} roughness={0.8} />
      </mesh>
    );
  return (
    <group
      ref={group}
      onClick={(event) => {
        event.stopPropagation();
        happyUntil.current = elapsed.current + 1.5;
        onPet?.();
      }}
    >
      {accessory === "glasses" && (
        <group position={[0, 1.02, 0.75]}>
          {[-0.29, 0.29].map((x) => (
            <mesh key={x} position={[x, 0, 0]}>
              <torusGeometry args={[0.18, 0.025, 8, 32]} />
              <meshStandardMaterial color="#3c324d" />
            </mesh>
          ))}
          <mesh>
            <boxGeometry args={[0.22, 0.025, 0.025]} />
            <meshStandardMaterial color="#3c324d" />
          </mesh>
        </group>
      )}
      {accessory === "headphones" && (
        <group>
          <mesh position={[0, 1.03, 0]}>
            <torusGeometry args={[0.9, 0.065, 8, 40, Math.PI]} />
            <meshStandardMaterial color="#554568" />
          </mesh>
          {[-0.86, 0.86].map((x) => (
            <mesh key={x} position={[x, 0.97, 0]} scale={[0.14, 0.29, 0.3]}>
              <sphereGeometry args={[1, 24, 16]} />
              <meshStandardMaterial color="#ac91d3" />
            </mesh>
          ))}
        </group>
      )}
      {(species === "cat" || species === "fox") && (
        <group position={[0.65, -0.2, -0.3]} rotation={[0, 0, -0.65]}>
          {sphere(
            [0, 0.3, 0],
            species === "fox" ? [0.3, 0.65, 0.3] : [0.13, 0.65, 0.13],
            coat,
            "tail",
          )}
          {species === "fox" &&
            sphere([0, 0.8, 0], [0.22, 0.22, 0.23], "#fff0dc", "tail-tip")}
        </group>
      )}
      {sphere(
        [0, 0.03, 0],
        species === "ghost" ? [0.77, 0.95, 0.55] : [0.68, 0.79, 0.52],
        coat,
        "body",
      )}
      {sphere(
        [0, 0.85, 0.025],
        species === "frog" ? [1, 0.58, 0.64] : [0.88, 0.73, 0.64],
        coat,
        "head",
      )}
      <group position={[-0.5, 1.45, 0]} rotation={[0, 0, 0.25]}>
        {sphere([0, 0, 0], earScale, coat, "ear-left")}
        {sphere(
          [0, 0.03, 0.18],
          [0.115, species === "bunny" ? 0.3 : 0.12, 0.055],
          "#f4d8cb",
          "inner-left",
        )}
      </group>
      <group position={[0.5, 1.45, 0]} rotation={[0, 0, -0.25]}>
        {sphere([0, 0, 0], earScale, coat, "ear-right")}
        {sphere(
          [0, 0.03, 0.18],
          [0.115, species === "bunny" ? 0.3 : 0.12, 0.055],
          "#f4d8cb",
          "inner-right",
        )}
      </group>
      {sphere([0, -0.03, 0.45], [0.43, 0.49, 0.1], "#eeedd9", "belly")}
      {sphere([-0.37, -0.59, 0.18], [0.31, 0.2, 0.37], coat, "foot-left")}
      {sphere([0.37, -0.59, 0.18], [0.31, 0.2, 0.37], coat, "foot-right")}
      <mesh
        ref={leftArm}
        position={[-0.67, 0.02, 0.03]}
        scale={[0.21, 0.4, 0.23]}
        castShadow
      >
        <sphereGeometry args={[1, 32, 24]} />
        <meshStandardMaterial color={coat} />
      </mesh>
      <mesh
        ref={rightArm}
        position={[0.67, 0.02, 0.03]}
        scale={[0.21, 0.4, 0.23]}
        castShadow
      >
        <sphereGeometry args={[1, 32, 24]} />
        <meshStandardMaterial color={coat} />
      </mesh>
      {sphere([0, 0.77, 0.55], [0.59, 0.36, 0.22], "#f3f0dd", "muzzle")}
      {species === "ghost" &&
        [-0.5, 0, 0.5].map((x) =>
          sphere([x, -0.72, 0], [0.28, 0.25, 0.46], coat, `hem-${x}`),
        )}
      <group ref={eyes} position={[0, 1.03, 0.61]}>
        {sphere([-0.29, 0, 0], [0.075, 0.105, 0.052], "#303c31", "eye-left")}
        {sphere([0.29, 0, 0], [0.075, 0.105, 0.052], "#303c31", "eye-right")}
        {sphere(
          [-0.31, 0.035, 0.043],
          [0.019, 0.024, 0.013],
          "#ffffff",
          "eye-light-left",
        )}
        {sphere(
          [0.27, 0.035, 0.043],
          [0.019, 0.024, 0.013],
          "#ffffff",
          "eye-light-right",
        )}
      </group>
      {sphere(
        [-0.48, 0.83, 0.66],
        [0.11, 0.055, 0.025],
        "#dda89a",
        "blush-left",
      )}
      {sphere(
        [0.48, 0.83, 0.66],
        [0.11, 0.055, 0.025],
        "#dda89a",
        "blush-right",
      )}
      <mesh geometry={smile}>
        <meshStandardMaterial color="#48503d" />
      </mesh>
      <mesh position={[0.04, 0.36, 0.55]} rotation={[0, 0, -0.12]}>
        <boxGeometry args={[0.22, 0.17, 0.07]} />
        <meshStandardMaterial color="#b7794e" roughness={0.9} />
      </mesh>
      {mood === "reminder" && (
        <group position={[0.95, 0.4, 0.28]} rotation={[0, -0.2, -0.2]}>
          <mesh>
            <boxGeometry args={[0.55, 0.65, 0.035]} />
            <meshStandardMaterial color="#f3d994" />
          </mesh>
          <mesh position={[0, 0.08, 0.025]}>
            <boxGeometry args={[0.3, 0.025, 0.01]} />
            <meshStandardMaterial color="#b59455" />
          </mesh>
          <mesh position={[-0.04, -0.04, 0.025]}>
            <boxGeometry args={[0.22, 0.025, 0.01]} />
            <meshStandardMaterial color="#b59455" />
          </mesh>
        </group>
      )}
    </group>
  );
}
class PetBoundary extends Component<
  { children: ReactNode; fallback: ReactNode },
  { error: boolean }
> {
  state = { error: false };
  static getDerivedStateFromError() {
    return { error: true };
  }
  render() {
    return this.state.error ? (
      <div
        className="pet-fallback"
        title="3D unavailable. Showing your illustrated companion."
      >
        {this.props.fallback}
      </div>
    ) : (
      this.props.children
    );
  }
}
export default function Pet(props: Props) {
  const [reaction, setReaction] = useState(false);
  useEffect(() => {
    if (reaction) {
      const t = setTimeout(() => setReaction(false), 1600);
      return () => clearTimeout(t);
    }
  }, [reaction]);
  const interact = () => {
    setReaction(true);
    props.onPet?.();
  };
  if (props.style === "2d")
    return (
      <button
        className={`pet-canvas pet-2d ${reaction ? "is-happy" : ""} mood-${props.mood}`}
        aria-label={`Pet your ${props.species || "bunny"} companion`}
        onClick={interact}
      >
        <PetIllustration
          species={props.species || "bunny"}
          accessory={props.accessory}
          color={props.color}
          happy={reaction}
          sleeping={props.mood === "sleeping"}
        />
        {reaction && <span className="pet-heart">♥</span>}
      </button>
    );
  return (
    <div
      className={`pet-canvas ${props.floating ? "floating-canvas" : ""}`}
      role="img"
      aria-label={`Your ${props.color} 3D companion, ${props.mood}`}
    >
      {reaction && <span className="pet-heart">♥</span>}
      <PetBoundary
        fallback={
          <PetIllustration
            species={props.species || "bunny"}
            accessory={props.accessory}
            color={props.color}
          />
        }
      >
        <Canvas
          shadows
          frameloop="demand"
          dpr={[1, 1.5]}
          camera={{ position: [0, 1.25, 6.5], fov: 34 }}
          gl={{ alpha: true, antialias: true, powerPreference: "low-power" }}
        >
          <Ticker />
          <ambientLight intensity={1.8} />
          <directionalLight
            position={[3, 5, 4]}
            intensity={2.4}
            castShadow
            shadow-mapSize={[512, 512]}
          />
          <directionalLight
            position={[-3, 2, -2]}
            intensity={1}
            color="#fff4df"
          />
          <Creature {...props} onPet={interact} />
          <mesh
            rotation={[-Math.PI / 2, 0, 0]}
            position={[0, -0.99, 0]}
            receiveShadow
          >
            <planeGeometry args={[20, 20]} />
            <shadowMaterial transparent opacity={0.12} />
          </mesh>
        </Canvas>
      </PetBoundary>
    </div>
  );
}
