# ComparaPrecios

App Flutter para comparar precios entre proveedores en cocina profesional.
Backend: **Firebase Firestore** (sincroniza móvil ↔ PC).
Identificador sugerido: `com.joseluengo.comparaprecios`.

## Qué hace
- **Comparativa (dashboard):** las tres métricas de un vistazo
  - proveedor más barato por producto
  - ahorro potencial total del catálogo
  - evolución del precio en el tiempo (gráfico por proveedor en cada producto)
- **Productos:** los creas tú y eliges la unidad de comparación (€/kg, €/L, €/ud).
- **Proveedores:** con color de identificación para los gráficos.
- **Precios:** cada alta es un registro histórico (no se sobrescribe), así sale gratis la evolución.

## Modelo de datos (Firestore)
```
proveedores/{id}
  nombre, contacto, notas, color (int ARGB), actualizado

productos/{id}
  nombre, nombreLower, categoria, unidadBase ("kg"|"litro"|"unidad"), notas, actualizado

precios/{id}            <-- histórico, no se edita, se añaden registros
  productoId, proveedorId
  precioPaquete         (lo que cuesta el formato, ej. caja 5kg = 12.50)
  cantidad              (formato en la unidad base, ej. 5)
  precioUnitario        (= precioPaquete / cantidad, el nº que compara)
  fecha (Timestamp)
  fuente ("manual"|"albaran")
  nota
```

"Precio actual" de un proveedor = su registro de `precios` más reciente.

## Puesta en marcha
1. Proyecto Flutter nuevo (o copia este `lib/` y `pubspec.yaml` a uno existente):
   ```
   flutter create comparaprecios
   ```
2. Copia el contenido de `lib/`, `pubspec.yaml` y `firestore.indexes.json`.
3. Conecta Firebase (genera `lib/firebase_options.dart`):
   ```
   dart pub global activate flutterfire_cli
   flutterfire configure
   ```
4. En Firebase Console activa **Cloud Firestore**.
5. Despliega el índice compuesto (consulta de precios por producto ordenados por fecha):
   ```
   firebase deploy --only firestore:indexes
   ```
   (o deja que Firestore te ofrezca el enlace para crearlo la primera vez que falle la consulta)
6. `flutter pub get` y a compilar (en tu caso, vía GitHub Actions).

## Reglas de Firestore sugeridas (de momento, uso personal sin login)
```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /{document=**} {
      allow read, write: if true;   // CAMBIAR antes de publicar
    }
  }
}
```
> Para producción, añade Firebase Auth y restringe a tu usuario.

## Siguiente paso natural: importar albaranes
La colección `precios` ya admite `fuente: "albaran"`. El flujo de Compras Semanales
(Cloudinary + visión para leer el albarán) puede volcar precios directamente aquí:
por cada línea del albarán → un `Precio.nuevo(... fuente: FuentePrecio.albaran)`.
Así la comparativa y los gráficos se alimentan solos.

## Estructura
```
lib/
  main.dart
  models/      proveedor.dart, producto.dart, precio.dart, comparativa.dart
  services/    firestore_service.dart, analitica_service.dart
  ui/          dashboard_screen.dart, productos_screen.dart,
               proveedores_screen.dart, producto_detalle_screen.dart, formato.dart
```
