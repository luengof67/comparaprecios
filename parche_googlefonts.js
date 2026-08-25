// Quita PdfGoogleFonts de los informes que lo usaban.
//
// PdfGoogleFonts DESCARGA la fuente de internet cada vez que se genera un
// PDF. Sin cobertura, el informe sale con cuadraditos donde deberia ir el
// simbolo del euro, o tarda, o falla. Con FuentesPdf la fuente va dentro de
// la app y funciona siempre.
//
// Uso:  node parche_googlefonts.js

const fs = require('fs');
const path = require('path');

const ARCHIVOS = [
  path.join('lib', 'services', 'hoja_pedido_service.dart'),
  path.join('lib', 'services', 'informe_compra_service.dart'),
  path.join('lib', 'services', 'informe_mensual_service.dart'),
  path.join('lib', 'ui', 'comparador_screen.dart'),
];

function morir(msg) {
  console.error('\n  ABORTADO: ' + msg + '\n  No se ha tocado ningun archivo.\n');
  process.exit(1);
}

// Primero se revisan TODOS, y solo si todos encajan se escribe alguno.
const plan = [];

for (const archivo of ARCHIVOS) {
  if (!fs.existsSync(archivo)) morir('no encuentro ' + archivo);

  const original = fs.readFileSync(archivo, 'utf8');
  let txt = original.replace(/\r\n/g, '\n');

  if (txt.includes('FuentesPdf.documento()')) {
    console.log('  (ya hecho) ' + archivo);
    continue;
  }

  // 1) las dos lineas que descargan la fuente
  const descargas = [...txt.matchAll(
    /^[ \t]*final \w+ = await PdfGoogleFonts\.\w+\(\);\n/gm)];
  if (descargas.length !== 2) {
    morir(archivo + ': esperaba 2 lineas de PdfGoogleFonts y hay '
        + descargas.length + '.');
  }

  // 2) el pw.Document( ... theme ... ) que las usa
  const doc = txt.match(
    /final doc = pw\.Document\(\s*\n\s*theme: pw\.ThemeData\.withFont\([\s\S]*?\),?\s*\n\s*\);/);
  if (!doc) morir(archivo + ': no encuentro el pw.Document con ThemeData.withFont.');

  plan.push({ archivo, original, txt, descargas, doc: doc[0] });
}

if (plan.length === 0) {
  console.log('\n  Nada que hacer.\n');
  process.exit(0);
}

// Aplicar
for (const p of plan) {
  let txt = p.txt;

  // fuera las descargas
  for (const d of p.descargas) txt = txt.replace(d[0], '');

  // el documento, con la sangria que tuviera
  const sangria = (p.doc.match(/^\s*/) || [''])[0];
  txt = txt.replace(p.doc, sangria + 'final doc = await FuentesPdf.documento();');

  // el import
  if (!txt.includes('fuentes_pdf.dart')) {
    const enServices = p.archivo.replace(/\\/g, '/').includes('lib/services/');
    const linea = "import '" + (enServices ? 'fuentes_pdf.dart'
                                           : '../services/fuentes_pdf.dart') + "';";
    const imports = [...txt.matchAll(/^import .*;$/gm)];
    const ultimo = imports[imports.length - 1];
    const corte = ultimo.index + ultimo[0].length;
    txt = txt.slice(0, corte) + '\n' + linea + txt.slice(corte);
  }

  if (txt.includes('PdfGoogleFonts')) {
    morir(p.archivo + ': ha quedado alguna referencia a PdfGoogleFonts.');
  }
  if (!txt.includes('final doc = await FuentesPdf.documento();')) {
    morir(p.archivo + ': no se ha escrito la llamada nueva.');
  }

  const eraCRLF = p.original.includes('\r\n');
  fs.writeFileSync(p.archivo + '.bak', p.original, 'utf8');
  fs.writeFileSync(p.archivo, eraCRLF ? txt.replace(/\n/g, '\r\n') : txt, 'utf8');
  console.log('  cambiado: ' + p.archivo);
}

console.log('\n  Listo. ' + plan.length + ' archivos.');
console.log('  Los PDFs ya no descargan la fuente: va dentro de la app.');
console.log('  Si el analyze avisa de un import de printing sin usar,');
console.log('  es normal, dimelo y lo quitamos.\n');
