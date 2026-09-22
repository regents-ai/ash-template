export const backgroundManifest = {
  home: "/images/backgrounds/home.svg",
  product: "/images/backgrounds/product.svg",
} as const

export type BackgroundSlot = keyof typeof backgroundManifest

export const isBackgroundSlot = (slot: string): slot is BackgroundSlot =>
  Object.prototype.hasOwnProperty.call(backgroundManifest, slot)
