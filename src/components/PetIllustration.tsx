import { petCatalog, type PetSpecies } from "../../shared/pets";
export function PetIllustration({
  species,
  color = "lilac",
  happy = false,
  sleeping = false,
  accessory = "none",
}: {
  species: PetSpecies;
  color?: string;
  happy?: boolean;
  sleeping?: boolean;
  accessory?: "none" | "glasses" | "headphones";
}) {
  const coat =
    species === "bunny"
      ? { sage: "#b9d3ac", peach: "#f0b9a1", lilac: "#c6b8f1" }[color] ||
        "#c6b8f1"
      : petCatalog.find((p) => p.id === species)!.color;
  return (
    <svg
      viewBox="0 0 260 240"
      aria-hidden="true"
      className={`pet-art species-${species}`}
    >
      <ellipse cx="130" cy="218" rx="58" ry="9" fill="#000" opacity=".12" />
      <g
        className="pet-body"
        stroke="#303044"
        strokeWidth="3.5"
        strokeLinejoin="round"
      >
        {species === "cat" && (
          <path
            d="M180 180 Q237 181 216 135"
            fill="none"
            stroke={coat}
            strokeWidth="20"
          />
        )}
        {species === "fox" && (
          <path d="M170 197 Q235 189 217 123 Q181 141 165 174" fill={coat} />
        )}
        {species === "ghost" ? (
          <path
            d="M66 120 Q66 52 130 52 Q194 52 194 120 L201 204 Q181 185 166 207 Q147 187 130 207 Q111 187 94 207 Q76 189 59 204Z"
            fill={coat}
          />
        ) : (
          <>
            <ellipse cx="130" cy="168" rx="55" ry="45" fill={coat} />
            <ellipse cx="130" cy="172" rx="32" ry="30" fill="#fff3df" />
            <ellipse cx="94" cy="207" rx="23" ry="12" fill={coat} />
            <ellipse cx="166" cy="207" rx="23" ry="12" fill={coat} />
          </>
        )}
        {species === "bunny" && (
          <>
            <path d="M88 83 Q49 -5 80 15 Q104 29 110 78" fill={coat} />
            <path d="M150 78 Q155 7 180 13 Q203 20 172 85" fill={coat} />
            <path
              d="M84 32 L97 68 M173 32 L162 68"
              stroke="#f3d2d4"
              strokeWidth="10"
              strokeLinecap="round"
            />
          </>
        )}
        {(species === "cat" || species === "fox") && (
          <>
            <path
              d="M67 103 L64 39 L111 73 M149 73 L197 39 L192 103"
              fill={coat}
            />
            <path
              d="M76 78 L76 58 L93 77 M168 77 L186 58 L184 80"
              fill="#f7d5c6"
              stroke="none"
            />
          </>
        )}
        {species === "bear" && (
          <>
            <circle cx="77" cy="76" r="23" fill={coat} />
            <circle cx="183" cy="76" r="23" fill={coat} />
            <circle cx="77" cy="76" r="11" fill="#efc9b3" stroke="none" />
            <circle cx="183" cy="76" r="11" fill="#efc9b3" stroke="none" />
          </>
        )}
        {species !== "ghost" && (
          <ellipse cx="130" cy="114" rx="71" ry="56" fill={coat} />
        )}
        {species === "frog" && (
          <>
            <circle cx="91" cy="70" r="24" fill={coat} />
            <circle cx="169" cy="70" r="24" fill={coat} />
          </>
        )}
        <g
          className="pet-eyes"
          transform={species === "frog" ? "translate(0,-27)" : ""}
        >
          {happy || sleeping ? (
            <path
              d="M94 110 Q103 100 112 110 M149 110 Q158 100 167 110"
              fill="none"
              strokeLinecap="round"
            />
          ) : (
            <>
              <ellipse cx="103" cy="108" rx="6" ry="9" fill="#303044" />
              <ellipse cx="157" cy="108" rx="6" ry="9" fill="#303044" />
              <circle cx="105" cy="105" r="2" fill="white" stroke="none" />
              <circle cx="159" cy="105" r="2" fill="white" stroke="none" />
            </>
          )}
        </g>
        <ellipse
          cx="84"
          cy="126"
          rx="12"
          ry="6"
          fill="#ec9a9f"
          opacity=".65"
          stroke="none"
        />
        <ellipse
          cx="176"
          cy="126"
          rx="12"
          ry="6"
          fill="#ec9a9f"
          opacity=".65"
          stroke="none"
        />
        {accessory === "glasses" && (
          <g
            fill="none"
            stroke="#39344b"
            strokeWidth="4"
            transform={species === "frog" ? "translate(0,-27)" : ""}
          >
            <circle cx="103" cy="108" r="18" />
            <circle cx="157" cy="108" r="18" />
            <path d="M121 107 Q130 101 139 107 M85 105 L67 99 M175 105 L193 99" />
          </g>
        )}
        {accessory === "headphones" && (
          <g>
            <path
              d="M62 119 Q49 48 130 47 Q211 48 198 119"
              fill="none"
              stroke="#656086"
              strokeWidth="11"
            />
            <rect x="55" y="99" width="18" height="37" rx="8" fill="#a693d8" />
            <rect x="187" y="99" width="18" height="37" rx="8" fill="#a693d8" />
          </g>
        )}
        <path
          d={happy ? "M118 127 Q130 151 142 127Z" : "M119 130 Q130 141 141 130"}
          fill={happy ? "#d78292" : "none"}
          strokeLinecap="round"
        />
        {species === "cat" && (
          <path
            d="M65 122 L44 116 M65 132 L43 135 M195 122 L216 116 M195 132 L217 135"
            strokeWidth="2"
          />
        )}
        {species !== "ghost" && (
          <>
            <ellipse
              className="pet-arm"
              cx="76"
              cy="168"
              rx="13"
              ry="24"
              fill={coat}
              transform="rotate(25 76 168)"
            />
            <ellipse
              cx="184"
              cy="168"
              rx="13"
              ry="24"
              fill={coat}
              transform="rotate(-25 184 168)"
            />
          </>
        )}
        <path
          d="M120 161 L130 168 L140 161 L140 178 L130 173 L120 178Z"
          fill="#8e7bc5"
          strokeWidth="2"
        />
      </g>
    </svg>
  );
}
