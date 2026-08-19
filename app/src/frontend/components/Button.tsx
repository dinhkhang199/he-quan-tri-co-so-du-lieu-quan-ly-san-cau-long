import type { ButtonHTMLAttributes, ReactNode } from 'react';
import { BpIcon } from './BpIcon';

type ButtonVariant = 'primary' | 'outline' | 'ghost' | 'danger' | 'secondary';
type ButtonSize = 'sm' | 'md' | 'lg';

interface ButtonProps extends ButtonHTMLAttributes<HTMLButtonElement> {
  variant?: ButtonVariant;
  size?: ButtonSize;
  /** Leading Material Symbol name. */
  icon?: string;
  /** Loading state: disables the button and swaps content for a spinner. */
  loading?: boolean;
  /** Keep children visible when loading (e.g. inside forms that already reserve space). */
  keepLabel?: boolean;
  fullWidth?: boolean;
  children?: ReactNode;
}

const VARIANT_CLASS: Record<ButtonVariant, string> = {
  primary: 'bp-btn--primary',
  secondary: 'bp-btn--secondary',
  outline: 'bp-btn--outline',
  ghost: 'bp-btn--ghost',
  danger: 'bp-btn--danger',
};

const SIZE_CLASS: Record<ButtonSize, string> = {
  sm: 'bp-btn--sm',
  md: 'bp-btn--md',
  lg: 'bp-btn--lg',
};

/**
 * BadmintonPro button. Primary uses the locked Stitch solid teal CTA;
 * outline/ghost/danger map to the prototype's structural actions.
 */
export function Button({
  variant = 'primary',
  size = 'md',
  icon,
  loading = false,
  keepLabel = false,
  fullWidth = false,
  className,
  disabled,
  children,
  ...rest
}: ButtonProps) {
  const classes = [
    'bp-btn',
    VARIANT_CLASS[variant],
    SIZE_CLASS[size],
    fullWidth ? 'bp-btn--full' : '',
    className ?? '',
  ]
    .filter(Boolean)
    .join(' ');

  return (
    <button className={classes} disabled={disabled || loading} {...rest}>
      {loading && !keepLabel ? <span className="bp-spinner" aria-hidden="true" /> : null}
      {icon ? <BpIcon name={icon} size={20} aria-hidden="true" /> : null}
      {keepLabel || children ? <span className="bp-btn__label">{children}</span> : null}
    </button>
  );
}