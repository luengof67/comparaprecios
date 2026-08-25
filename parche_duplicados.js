// Añade a Mantenimiento la tarjeta de "Proveedores repetidos".
// Uso:  node parche_duplicados.js

const fs = require('fs');
const path = require('path');

const ARCHIVO = path.join('lib', 'ui', 'mantenimiento_screen.dart');

function morir(msg) {
  console.error('\n  ABORTADO: ' + msg + '\n  El archivo NO se ha tocado.\n');
  process.exit(1);
}

if (!fs.existsSync(ARCHIVO)) morir('no encuentro ' + ARCHIVO);

const original = fs.readFileSync(ARCHIVO, 'utf8');
const eraCRLF = original.includes('\r\n');
let txt = original.replace(/\r\n/g, '\n');

if (txt.includes('DuplicadosScreen')) {
  console.log('\n  Ya estaba puesto.\n');
  process.exit(0);
}

function unico(aguja, nombre) {
  let n = 0, i = 0;
  while ((i = txt.indexOf(aguja, i)) !== -1) { n++; i += aguja.length; }
  if (n !== 1) morir('el ancla "' + nombre + '" aparece ' + n + ' veces (esperaba 1).');
}

const A_IMPORT = "import 'huerfanos_screen.dart';";
unico(A_IMPORT, 'import de huerfanos_screen (falta el parche anterior?)');

const A_LISTA = "          if (_guardadas.isNotEmpty) ...[";
unico(A_LISTA, 'bloque de copias guardadas');

const TARJETA =
  "          const SizedBox(height: 12),\n" +
  "          Card(\n" +
  "            child: Padding(\n" +
  "              padding: const EdgeInsets.all(16),\n" +
  "              child: Column(\n" +
  "                crossAxisAlignment: CrossAxisAlignment.start,\n" +
  "                children: [\n" +
  "                  Row(\n" +
  "                    children: [\n" +
  "                      const Icon(Icons.content_copy),\n" +
  "                      const SizedBox(width: 8),\n" +
  "                      Text('Proveedores repetidos',\n" +
  "                          style: Theme.of(context).textTheme.titleMedium),\n" +
  "                    ],\n" +
  "                  ),\n" +
  "                  const SizedBox(height: 8),\n" +
  "                  const Text(\n" +
  "                    'El mismo proveedor con dos fichas, por estar escrito '\n" +
  "                    'de dos formas. Su histórico de precios queda partido y '\n" +
  "                    'la comparativa los trata como si compitieran entre sí.',\n" +
  "                    style: TextStyle(fontSize: 13),\n" +
  "                  ),\n" +
  "                  const SizedBox(height: 14),\n" +
  "                  OutlinedButton.icon(\n" +
  "                    icon: const Icon(Icons.search),\n" +
  "                    label: const Text('Buscar repetidos'),\n" +
  "                    onPressed: () => Navigator.push(\n" +
  "                      context,\n" +
  "                      MaterialPageRoute(\n" +
  "                          builder: (_) => DuplicadosScreen(db: widget.db)),\n" +
  "                    ),\n" +
  "                  ),\n" +
  "                ],\n" +
  "              ),\n" +
  "            ),\n" +
  "          ),\n" +
  A_LISTA;

txt = txt.replace(A_IMPORT, A_IMPORT + "\nimport 'duplicados_screen.dart';");
txt = txt.replace(A_LISTA, TARJETA);

for (const m of ["import 'duplicados_screen.dart';",
                 "DuplicadosScreen(db: widget.db)"]) {
  if (!txt.includes(m)) morir('no se ha escrito: ' + m);
}
unico(A_LISTA, 'bloque de copias guardadas (despues)');

fs.writeFileSync(ARCHIVO + '.bak', original, 'utf8');
fs.writeFileSync(ARCHIVO, eraCRLF ? txt.replace(/\n/g, '\r\n') : txt, 'utf8');

console.log('\n  Listo.');
console.log('  - import de duplicados_screen');
console.log('  - tarjeta "Proveedores repetidos"');
console.log('  - copia en ' + ARCHIVO + '.bak\n');
