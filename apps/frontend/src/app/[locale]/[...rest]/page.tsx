// Unmatched URLs, so the 404 is the localised one (ADR-0400).
import { notFound } from "next/navigation";

export default function CatchAllNotFound() {
  notFound();
}
