// Añade a FirestoreService la fusion entre dos proveedores que EXISTEN.
//
// La de ayer (reasignarProveedor) solo movia el historico, porque el origen
// era un id sin ficha. Aqui el origen tiene ficha propia, asi que ademas hay
// que borrarla: si no, se queda una ficha vacia en la lista.
//
// Uso:  node parche_fusion.js

const fs = require('fs');
const path = require('path');

const ARCHIVO = path.join('lib', 'services', 'firestore_service.dart');

function morir(msg) {
  console.error('\n  ABORTADO: ' + msg + '\n  El archivo NO se ha tocado.\n');
  process.exit(1);
}

if (!fs.existsSync(ARCHIVO)) morir('no encuentro ' + ARCHIVO);

const original = fs.readFileSync(ARCHIVO, 'utf8');
const eraCRLF = original.includes('\r\n');
let txt = original.replace(/\r\n/g, '\n');

if (txt.includes('fusionarProveedores')) {
  console.log('\n  Ya estaba puesto.\n');
  process.exit(0);
}

const ANCLA = '  /// Borra los precios de un proveedor. Con [soloTarifa] en true respeta los';
let n = 0, i = 0;
while ((i = txt.indexOf(ANCLA, i)) !== -1) { n++; i += ANCLA.length; }
if (n !== 1) morir('el ancla aparece ' + n + ' veces (esperaba 1). '
    + 'Falta el parche de ayer?');

const NUEVO = `  /// Fusiona dos proveedores que EXISTEN los dos: mueve todo el historico
  /// de [de] a [a] y despues borra la ficha de [de].
  ///
  /// Es lo que hace falta cuando el mismo proveedor real quedo con dos fichas
  /// (mismo nombre escrito de dos formas). A diferencia de reasignar un id
  /// huerfano, aqui hay una ficha de sobra que hay que quitar de en medio.
  ///
  /// El borrado va al final a proposito: si algo falla moviendo el historico,
  /// la ficha origen sigue ahi y no se pierde el rastro de a quien pertenecia.
  ///
  /// OJO: no se puede deshacer.
  Future<({int precios, int compras})> fusionarProveedores({
    required String de,
    required String a,
    required String nombreDestino,
  }) async {
    if (de == a) {
      throw ArgumentError('No se puede fusionar un proveedor consigo mismo.');
    }

    final r = await reasignarProveedor(
      de: de,
      a: a,
      nombreDestino: nombreDestino,
    );

    await _proveedores.doc(de).delete();
    return r;
  }

` + ANCLA;

txt = txt.replace(ANCLA, NUEVO);

if (!txt.includes('fusionarProveedores')) morir('no se ha escrito el metodo.');
if (!txt.includes('await _proveedores.doc(de).delete();')) morir('falta el borrado.');

fs.writeFileSync(ARCHIVO + '.bak', original, 'utf8');
fs.writeFileSync(ARCHIVO, eraCRLF ? txt.replace(/\n/g, '\r\n') : txt, 'utf8');

console.log('\n  Listo. Añadido fusionarProveedores.');
console.log('  Copia en ' + ARCHIVO + '.bak\n');
