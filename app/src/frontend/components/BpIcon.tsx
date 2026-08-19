interface BpIconProps {
  name: string;
  /** Fill the icon (uses Material Symbols FILL 1). */
  filled?: boolean;
  size?: number | string;
  className?: string;
  label?: string;
}

/** Material Symbols Outlined wrapper (locked Stitch icon set). */
export function BpIcon({ name, filled = false, size = 24, className, label }: BpIconProps) {
  return (
    <span
      className={`material-symbols-outlined bp-icon${filled ? ' bp-icon--filled' : ''}${className ? ` ${className}` : ''}`}
      style={{ fontVariationSettings: filled ? 'FILL 1' : 'FILL 0', fontSize: size }}
      role={label ? 'img' : undefined}
      aria-label={label}
      aria-hidden={label ? undefined : true}
    >
      {name}
    </span>
  );
}