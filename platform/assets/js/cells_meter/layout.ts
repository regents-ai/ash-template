/**
 * Where the Cells meter's cells sit, worked out exactly as the design system's
 * cells.css places the still ones, so the moving picture lands on the same grid
 * pixel for pixel: the bar is as many whole cells as fit across, and each run
 * starts and ends on the nearest cell edge.
 */

/** The meter's measures in CSS pixels, from `--rg-cells-cell`, `--rg-cells-gap` and `--rg-cells-rows`. */
export type Grid = {cell: number; gap: number; rows: number}

/** A run of cells: the columns from `from` up to, not including, `to`. */
export type Run = {from: number; to: number}

/** How many whole cells fit across a bar `width` CSS pixels wide. */
export const columnsIn = (width: number, grid: Grid): number =>
  Math.max(0, Math.floor((width + grid.gap) / (grid.cell + grid.gap)))

/**
 * The columns a part covers in a bar `columns` cells wide, from its start and share
 * of the capacity. Both edges round to the nearest cell edge, a half rounding up, as
 * CSS `round()` does, so a part's run ends exactly where the next one's starts.
 */
export const runOf = (start: number, share: number, columns: number): Run => ({
  from: Math.round(start * columns),
  to: Math.round((start + share) * columns),
})

/** The bar's height in CSS pixels. */
export const barHeight = (grid: Grid): number => grid.rows * (grid.cell + grid.gap) - grid.gap
