/* Fine Line: thin outlines, a little dither, soft shade where surfaces meet. outline is how readily an edge gets the ink colour, dither
   how much two palette colours are mixed in a pattern, shade the contact shadow's strength and reach, grain the noise in shading. */
module.exports = { kind: 'finish', outline: 0.7, dither: 0.3, shade: { k: 0.4, range: 0.5 }, grain: 0.05 };
