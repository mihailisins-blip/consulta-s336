/**
 * PDF mínimo de una página con tres líneas de texto en las dos fuentes base
 * (Helvetica y Helvetica-Bold): un título de 18 pt en negrita, una línea normal
 * de 11 pt y una de 11 pt en negrita. Sirve para probar que `pdfToLines` da el
 * tamaño y la negrita de cada línea.
 * @returns {Buffer}
 */
export function pdfConTexto() {
  const contenido = [
    'BT /F2 18 Tf 50 700 Td (Titulo de fase) Tj ET',
    'BT /F1 11 Tf 50 650 Td (Texto normal del paso) Tj ET',
    'BT /F2 11 Tf 50 630 Td (Texto en negrita) Tj ET',
  ].join('\n');
  const partes = [];
  const offsets = [];
  let pos = 0;
  const push = (s) => { const b = Buffer.from(s, 'latin1'); partes.push(b); pos += b.length; };
  push('%PDF-1.4\n');
  const obj = (n, cuerpo) => { offsets[n] = pos; push(`${n} 0 obj\n${cuerpo}\nendobj\n`); };
  obj(1, '<< /Type /Catalog /Pages 2 0 R >>');
  obj(2, '<< /Type /Pages /Kids [3 0 R] /Count 1 >>');
  obj(3, '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R /Resources << /Font << /F1 5 0 R /F2 6 0 R >> >> >>');
  obj(4, `<< /Length ${contenido.length} >>\nstream\n${contenido}\nendstream`);
  obj(5, '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>');
  obj(6, '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold /Encoding /WinAnsiEncoding >>');
  const xref = pos;
  push(`xref\n0 7\n0000000000 65535 f \n${[1, 2, 3, 4, 5, 6].map((n) => `${String(offsets[n]).padStart(10, '0')} 00000 n \n`).join('')}`);
  push(`trailer\n<< /Size 7 /Root 1 0 R >>\nstartxref\n${xref}\n%%EOF\n`);
  return Buffer.concat(partes);
}

/**
 * PDF mínimo de una página con dos imágenes RGB sin comprimir: una grande
 * (400x200 pt, la que interesa) y un logotipo pequeño (100x10 pt, descartable).
 * Sin texto: el parseo de VMI lo deja como `sinExtraer`, que basta para probar
 * la extracción de imágenes y la plomería (pool, caché) sin un VMI real de 5 MB.
 * @returns {Buffer}
 */
export function pdfConImagenes() {
  const rgb = Buffer.alloc(4 * 2 * 3);
  for (let i = 0; i < rgb.length; i += 3) { rgb[i] = 200; rgb[i + 1] = 30; rgb[i + 2] = 30; }
  const img = (n) => `${n} 0 obj\n<< /Type /XObject /Subtype /Image /Width 4 /Height 2 /ColorSpace /DeviceRGB /BitsPerComponent 8 /Length ${rgb.length} >>\nstream\n`;
  const contenido = 'q 400 0 0 200 50 300 cm /Im0 Do Q\nq 100 0 0 10 50 100 cm /Im1 Do Q\n';
  const partes = [];
  const offsets = [];
  let pos = 0;
  const push = (b) => { const buf = Buffer.isBuffer(b) ? b : Buffer.from(b, 'latin1'); partes.push(buf); pos += buf.length; };
  push('%PDF-1.4\n');
  const obj = (n, cuerpo) => { offsets[n] = pos; push(`${n} 0 obj\n${cuerpo}\nendobj\n`); };
  obj(1, '<< /Type /Catalog /Pages 2 0 R >>');
  obj(2, '<< /Type /Pages /Kids [3 0 R] /Count 1 >>');
  obj(3, '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R /Resources << /XObject << /Im0 5 0 R /Im1 6 0 R >> >> >>');
  obj(4, `<< /Length ${contenido.length} >>\nstream\n${contenido}endstream`);
  for (const n of [5, 6]) {
    offsets[n] = pos;
    push(img(n)); push(rgb); push('\nendstream\nendobj\n');
  }
  const xref = pos;
  push(`xref\n0 7\n0000000000 65535 f \n${[1, 2, 3, 4, 5, 6].map((n) => `${String(offsets[n]).padStart(10, '0')} 00000 n \n`).join('')}`);
  push(`trailer\n<< /Size 7 /Root 1 0 R >>\nstartxref\n${xref}\n%%EOF\n`);
  return Buffer.concat(partes);
}
