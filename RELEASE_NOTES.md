# Signer App 1.0.0

Primera versión estable de Signer App: aplicación de escritorio (Windows) para firmar electrónicamente archivos PDF.

## Instalación

1. Descarga `Signer-App-1.0.0-win-x64.zip`.
2. Extrae el ZIP a una carpeta de tu elección.
3. Ejecuta `signer_app.exe`. Es portable: no requiere instalación.

## Características

- **Firma digital (X.509, SHA-256, CMS/PKCS#7)** con certificado local PFX/P12.
- **Rúbrica opcional**: dibuja o importa tu rúbrica (PNG) y colócala sobre cualquier página.
- **Certificados reutilizables** con contraseña protegida (Credential Manager / DPAPI).
- **Sello de tiempo (TSA RFC 3161)** opcional, con estado visible en el resumen de firma.
- **Verificación de firma**: integridad, cadena de certificados y revocación (CRL).
- **Firma por lotes** con diálogo de sobrescritura (sobrescribir / renombrar / cancelar, «aplicar a todo»).
- **PDFs protegidos**: abre PDFs con contraseña de apertura.
- **Detección de firmas existentes** y aviso al usuario.
- Guardado seguro: `nombre_firmado.pdf` (o `nombre_firmado_2.pdf` si ya existe).

## Notas técnicas

- Compilado con Flutter 3.19.2 / Dart 3.3.0, plataforma Windows x64.
- Revocación y TSA son *soft-fail*: nunca invalidan la firma si fallan por red.
- El sello de tiempo se guarda en un archivo sidecar `{archivo}.tsr` junto al PDF firmado (Syncfusion 25.1.39 no lo embebe).

## Verificación

- `flutter analyze`: sin issues.
- `flutter test`: 78/78 en verde.
