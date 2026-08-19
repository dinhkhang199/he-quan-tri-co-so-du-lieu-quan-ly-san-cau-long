import type { ButtonHTMLAttributes } from 'react';
import { BpIcon } from './BpIcon';

interface IconButtonProps extends ButtonHTMLAttributes<HTMLButtonElement> {
  icon: string;
  label: string;
  filled?: boolean;
  /** Render an error color dot (unread/notification affordance). */
  badge?: boolean;
  size?: 'sm' | 'md' | 'lg';
  className?: string;
}

const SIZE_CLASS: Record<string, string> = {
  sm: 'bp-icon-btn--sm',
  md: 'bp-icon-btn--md',
  lg: 'bp-icon-btn--lg',
};

/** Icon-only round button (locked Stitch top-bar actions). */
export function IconButton({
  icon,
  label,
  filled = false,
  badge = false,
  size = 'md',
  className,
  ...rest
}: IconButtonProps) {
  const iconSize = size === 'lg' ? 28 : size === 'sm' ? 18 : 22;
  return (
    <button
      className={['bp-icon-btn', SIZE_CLASS[size], className ?? ''].filter(Boolean).join(' ')}
      aria-label={label}
      title={label}
      {...rest}
    >
      <BpIcon name={icon} filled={filled} size={iconSize} aria-hidden="true" />
      {badge ? <span className="bp-icon-btn__dot" aria-hidden="true" /> : null}
    </button>
  );
}