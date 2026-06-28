# Firma y build por GitHub Actions

Reutilizas tu **keystore compartido** de siempre. No hace falta uno nuevo:
una keystore puede firmar varias apps. Solo el `applicationId` cambia
(`com.joseluengo.comparaprecios`).

## 1. Secrets que tienes que crear en el repo
En GitHub → Settings → Secrets and variables → Actions → New repository secret:

| Secret              | Qué es                                              |
|---------------------|-----------------------------------------------------|
| `KEYSTORE_BASE64`   | tu .jks en base64 (ver abajo cómo generarlo)        |
| `KEYSTORE_PASSWORD` | contraseña del almacén (storePassword)              |
| `KEY_PASSWORD`      | contraseña de la clave (keyPassword)                |
| `KEY_ALIAS`         | alias de la clave dentro del keystore               |

Generar el base64 de tu keystore (en tu PC):
```bash
# Linux / Git Bash
base64 -w0 mi-keystore.jks > keystore.b64
# Windows PowerShell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("mi-keystore.jks")) > keystore.b64
```
Abre `keystore.b64`, copia TODO el texto y pégalo como valor de `KEYSTORE_BASE64`.

> El workflow ya reconstruye `android/app/keystore.jks` y `android/key.properties`
> a partir de estos secrets en cada build. No subas el keystore al repo.

## 2. Configurar la firma en Gradle
`flutter create` en tu versión genera **Kotlin DSL** (`build.gradle.kts`).
Edita `android/app/build.gradle.kts`:

```kotlin
import java.util.Properties
import java.io.FileInputStream

// ...arriba del bloque android { ... }
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    // ...

    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as String?
            keyPassword = keystoreProperties["keyPassword"] as String?
            storeFile = keystoreProperties["storeFile"]?.let { file(it) }
            storePassword = keystoreProperties["storePassword"] as String?
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            // isMinifyEnabled = true   // opcional
        }
    }
}
```

### Si tu proyecto usara Groovy (`build.gradle` clásico)
```groovy
def keystoreProperties = new Properties()
def keystorePropertiesFile = rootProject.file('key.properties')
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(new FileInputStream(keystorePropertiesFile))
}

android {
    signingConfigs {
        release {
            keyAlias keystoreProperties['keyAlias']
            keyPassword keystoreProperties['keyPassword']
            storeFile keystoreProperties['storeFile'] ? file(keystoreProperties['storeFile']) : null
            storePassword keystoreProperties['storePassword']
        }
    }
    buildTypes {
        release {
            signingConfig signingConfigs.release
        }
    }
}
```

## 3. .gitignore (importante)
Asegúrate de NO subir secretos. Añade a `.gitignore`:
```
android/key.properties
android/app/keystore.jks
*.jks
*.b64
```
> En cambio, SÍ se suben al repo: `lib/firebase_options.dart` y
> `android/app/google-services.json`. Las claves de Firebase para cliente
> no son secretas (se protegen con las reglas de Firestore), y Actions las
> necesita para compilar.

## 4. Lanzar un build
- Manual: pestaña **Actions** → workflow "Build" → **Run workflow**.
- Por versión: crea un tag y empuja:
  ```bash
  git tag v1.0.0
  git push origin v1.0.0
  ```
Al terminar, descarga el artefacto **comparaprecios-release**: dentro tienes
el `app-release.apk` (sideload al Samsung) y el `app-release.aab` (Google Play).

## 5. compileSdk / versiones
Si Actions se queja de versiones, alinéalo con tu stack actual en
`android/app/build.gradle.kts`: `compileSdk = 36`, `minSdk = 23` o superior.
Tu toolchain (AGP 8.11.1, Kotlin 2.2.20, Gradle 8.14.1) es compatible.
