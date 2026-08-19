import type { InputHTMLAttributes } from 'react';
import { useId } from 'react';
import { BpIcon } from './BpIcon';

interface InputProps extends InputHTMLAttributes<HTMLInputElement> {
  label?: string;
  /** Leading Material Symbol name. */
  icon?: string;
  error?: string | null;
  hint?: string;
  fullWidth?: boolean;
}

/**
 * BadmintonPro text input with optional label/icon/error, styled to the
 * locked Stitch login/court-search form controls.
 */
export function Input({
  label,
  icon,
  error,
  hint,
  fullWidth = false,
  className,
  id,
  ...rest
}: InputProps) {
  const autoId = useId();
  const inputId = id ?? autoId;
  const errorId = `${inputId}-error`;
  const hintId = `${inputId}-hint`;
  return (
    <div className={`bp-field${fullWidth ? ' bp-field--full' : ''}${className ? ` ${className}` : ''}`}>
      {label ? (
        <label className="bp-field__label" htmlFor={inputId}>
          {label}
        </label>
      ) : null}
      <div className={`bp-field__control${error ? ' bp-field__control--error' : ''}`}>
        {icon ? (
          <span className="bp-field__icon">
            <BpIcon name={icon} size={20} aria-hidden="true" />
          </span>
        ) : null}
        <input
          id={inputId}
          className="bp-field__input"
          aria-invalid={error ? true : undefined}
          aria-describedby={error ? errorId : hint ? hintId : undefined}
          {...rest}
        />
      </div>
      {error ? (
        <p className="bp-field__error" id={errorId}>
          {error}
        </p>
      ) : hint ? (
        <p className="bp-field__hint" id={hintId}>
          {hint}
        </p>
      ) : null}
    </div>
  );
}

interface SearchInputProps extends Omit<InputProps, 'icon'> {
  leadingIcon?: string;
}

/** Pill-shaped search box per the locked guest/manager search inputs. */
export function SearchInput({ leadingIcon = 'search', placeholder = 'Tìm kiếm...', ...rest }: SearchInputProps) {
  return <Input icon={leadingIcon} placeholder={placeholder} className="bp-search" {...rest} />;
}