# Signer App

Aplicación de escritorio (Windows) para firmar electrónicamente archivos PDF.

- **Firma digital obligatoria**: incrusta una firma electrónica criptográfica (X.509,
  SHA-256, CMS/PKCS#7) usando un certificado local PFX/P12 que se elige primero.
- **Rúbrica opcional**: dibuja o importa tu rúbrica (PNG) y colócala arrastrándola
  sobre cualquier página del visor; si no hay rúbrica, se sella con una apariencia de
  texto estándar («Firmado digitalmente por …»).
- Certificados reutilizables; la contraseña del PFX puede guardarse en el almacenamiento
  seguro del sistema (Credential Manager / DPAPI de Windows) y se valida al configurarlo.
- El PDF firmado se guarda como `nombre_firmado.pdf` junto al original y se abre al
  terminar.

## Requisitos de compilación

- Flutter/Dart con plugins nativos en Windows requiere **Developer Mode** activado:
  `Inicio → Configuración → Privacidad y seguridad → Para desarrolladores → Modo de
  desarrollador`. Es necesario por los symlinks que crean los paquetes con código nativo
  (`pdfrx` y otros).
- Visual Studio 2022 con la “Carga de trabajo: desarrollo para escritorio con C++”.
- CMake y Ninja.

## Stack

| Uso                | Paquete                    |
| ------------------ | -------------------------- |
| Visor de PDF       | `pdfrx` (PDFium)           |
| Firma digital      | `syncfusion_flutter_pdf`   |
| Gestión de estado  | `flutter_riverpod`         |
| Archivos           | `file_picker`, `open_filex`|
| Persistencia       | `shared_preferences`, `flutter_secure_storage` |
| Ventanas           | `window_manager`           |

## Licencia

`syncfusion_flutter_pdf` de Syncfusion se distribuye bajo licenciamiento Community:
gratuita para empresas con menos de 1 M USD de ingresos anuales y menos de 5
desarrolladores. En las versiones usadas aquí el registro de clave de licencia ya
no es necesario.

## Desarrollo

```sh
flutter pub get
flutter run -d windows
```

## Pruebas

```sh
flutter test
flutter analyze
```