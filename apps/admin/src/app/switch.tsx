"use client";
// A boolean field. The checkbox posts with the form, and aria-checked follows it, so assistive tools read the state.
import { type ChangeEvent, useCallback, useState } from "react";

export function Switch({ id, name, initial }: { id: string; name: string; initial: boolean }) {
  const [on, setOn] = useState(initial);
  const toggle = useCallback(
    (event: ChangeEvent<HTMLInputElement>) => setOn(event.target.checked),
    [],
  );
  return (
    <input
      id={id}
      name={name}
      type="checkbox"
      role="switch"
      aria-checked={on}
      checked={on}
      onChange={toggle}
    />
  );
}
