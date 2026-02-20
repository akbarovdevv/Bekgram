# Bekgram (Flutter + MySQL + Realtime Socket)

## 1. MySQL bazani yaratish

`server/sql/init.sql` ichida `bekgram_local` database va `bekgram_app` user tayyor.

```bash
cd server
./scripts/setup_mysql.sh
```

Agar `root` password so'rasa, kiriting.

## 2. Backend serverni ishga tushirish

```bash
cd server
cp .env.example .env
npm install
npm run start
```

Server: `http://localhost:3000`
Health: `http://localhost:3000/api/health`

## 3. Flutter appni ishga tushirish

```bash
flutter pub get
flutter run -d chrome
```

Android emulator (Chrome sekin bo'lsa tavsiya):

```bash
flutter emulators
flutter emulators --launch <emulator_id>
flutter run -d <device_id>
```

Eslatma:
- Android emulator uchun `API_HOST` default ravishda `10.0.2.2` bo'lib ishlaydi.
- Telefon (real device) ulasangiz, hostni qo'lda bering:

```bash
flutter run -d <device_id> --dart-define=API_HOST=192.168.1.34 --dart-define=API_PORT=3000
```

Yoki web build:

```bash
flutter build web --no-wasm-dry-run
python3 -m http.server 8080 --directory build/web
```

## 4. Telefon (iPhone) uchun

Agar iPhone orqali ko'rsangiz, backend host ham telefon uchun ochiq bo'lishi kerak.

Misol build:

```bash
flutter build web --dart-define=API_HOST=192.168.1.34 --dart-define=API_PORT=3000
```

Keyin frontend: `http://192.168.1.34:8080`
Backend: `http://192.168.1.34:3000`

## API stack

- Auth: JWT
- DB: MySQL/MariaDB
- Realtime: Socket.IO (`message:new`, `chat:updated`, `presence:update`)
