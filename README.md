# FireFly · App para iPhone (MVP v1)

App en SwiftUI para iOS 27 o superior. Sigue el prototipo de Figma «FireFly – Prototipo app».

Incluye las historias imprescindibles del MVP (sección 2.3 del portafolio):

| # | Historia | En la app |
|---|---|---|
| 1 | El router sigue con internet cuando se va la luz | Lo hace la batería. La app muestra el aviso de corte y el tiempo que queda. |
| 2 | Entrar con Google | Pantalla de inicio de sesión (Firebase Auth + Google). |
| 3 | Vincular la batería con el QR | Cámara con lector de QR (VisionKit) o código escrito a mano. |
| 4 | Ver el porcentaje y las horas restantes | Panel principal en vivo. |
| 5 | Historial con filtros (no imprescindible) | Día / Semana / Mes / Año con gráfico. |

También tiene avisos («Se fue la luz», «Batería baja», «Volvió la luz») y el interruptor «Cargar también con la corriente».

## Dos formas de usarla

- **Modo demo:** si la app no tiene `GoogleService-Info.plist`, arranca sola en modo demo. La batería se simula dentro del teléfono y en Ajustes hay un botón para simular un corte. Sirve para probarla hoy mismo.
- **Modo real (Firebase):** con `GoogleService-Info.plist`, el inicio de sesión es con Google y los datos vienen de Firestore. Mientras no exista el ESP32, los envía el **simulador** (`simulador/`).

## 1. Instalar lo necesario (una sola vez)

1. Instala **Xcode** desde la App Store (gratis, ~15–20 GB) y ábrelo una vez para que termine de instalar sus componentes.
2. En la Terminal:
   ```bash
   sudo xcode-select -s /Applications/Xcode.app
   ```
3. XcodeGen ya está instalado. Si en otra Mac no lo está: `brew install xcodegen`.

## 2. Abrir y correr la app (modo demo)

```bash
cd FireFly-iOS
xcodegen generate
open FireFly.xcodeproj
```

En Xcode:
1. La primera vez descarga los paquetes de Firebase y Google Sign-In; espera a que termine.
2. Selecciona el destino **iPhone** (simulador) y presiona ▶.

### En tu iPhone

1. Conecta el iPhone por cable y activa **Modo de desarrollador** (Ajustes → Privacidad y seguridad).
2. En Xcode: proyecto **FireFly** → pestaña **Signing & Capabilities** → **Team**: tu Apple ID (Add Account si no aparece).
3. Si dice que el identificador ya existe, cambia **Bundle Identifier** por uno tuyo, por ejemplo `ec.edu.utpl.firefly.jalvarez`.
4. Elige tu iPhone como destino y presiona ▶. En el iPhone acepta el certificado en Ajustes → General → VPN y gestión de dispositivos.

Con un Apple ID gratis la app dura 7 días en el teléfono; luego se vuelve a instalar desde Xcode.

## 3. Conectar Firebase (modo real)

1. Entra a <https://console.firebase.google.com> y crea el proyecto **FireFly**.
2. **Authentication** → Métodos de acceso → activa **Google**.
3. **Firestore Database** → Crear base de datos → región **us-east1** (como dice la sección 2.4).
4. **Reglas** de Firestore: pega el contenido de `firebase/firestore.rules` y publica.
5. Configuración del proyecto → **Agregar app iOS** con el mismo Bundle Identifier que usas en Xcode. Descarga `GoogleService-Info.plist` y cópialo en la carpeta `FireFly/` del proyecto.
6. Abre `GoogleService-Info.plist`, copia el valor de **REVERSED_CLIENT_ID** y pégalo en `project.yml` en lugar de `com.googleusercontent.apps.REEMPLAZAR`.
7. Vuelve a generar el proyecto y córrelo:
   ```bash
   xcodegen generate
   open FireFly.xcodeproj
   ```

`GoogleService-Info.plist` y la clave del simulador no se suben a ningún repositorio (están en `.gitignore`).

## 4. Batería simulada

Hace lo mismo que hará el ESP32: escribe el estado de la batería en Firestore y registra cada corte.

1. Firebase → Configuración del proyecto → **Cuentas de servicio** → Generar nueva clave privada. Guárdala como `simulador/clave-servicio.json`.
2. En la Terminal:
   ```bash
   cd simulador
   npm install
   node simulador.js crear FF-0231
   ```
   Esto crea la batería y su código QR en `QR/FF-0231.png`. Imprímelo o ábrelo en otra pantalla para escanearlo con la app. También muestra el código para escribirlo a mano.
3. Opcional, para que el historial tenga datos (quedan marcados como simulados):
   ```bash
   node simulador.js historial FF-0231
   ```
4. Simulación en vivo. Teclas: **c** = se fue la luz, **l** = volvió la luz, **q** = salir.
   ```bash
   node simulador.js correr FF-0231 --rapido
   ```
   Con `--rapido` cada segundo cuenta como un minuto. Sin la opción, la simulación va en tiempo real.
5. Para vincular la batería a otra cuenta: `node simulador.js liberar FF-0231`.

En modo demo, el código de prueba es `QR/FF-0231-demo.png`, o se escribe a mano `FF-0231 DEMO`.

## Estructura

```
FireFly/
  App/        arranque de la app y estado central (AppModel)
  Models/     datos de la batería, cortes y cálculos del historial
  Services/   Firebase, modo demo y avisos
  Theme/      colores y estilos del Figma
  Views/      pantallas: inicio de sesión, vincular, panel, historial, ajustes
firebase/     reglas de Firestore
simulador/    batería simulada (Node.js)
QR/           códigos QR de prueba
```

## Límites conocidos del MVP

- Los avisos son **locales**: llegan cuando la app ve el cambio, sobre todo si está abierta o se abrió hace poco. Para avisos con la app cerrada hacen falta las notificaciones push (Firebase Cloud Messaging), que requieren la cuenta Apple Developer de USD 99 al año.
- La autonomía y los tiempos de carga son estimaciones con una batería de ~150 Wh y un router de 9,8 W. Hay que medirlos con el prototipo real.
- Los títulos usan la letra redondeada del sistema. Para usar Space Grotesk como en el Figma, agrega `SpaceGrotesk-Bold.ttf` a la app y regístrala en `Info.plist` (`UIAppFonts`); la app la usa sola si la encuentra.
