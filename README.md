# Background Remover

Flutter app xóa nền ảnh tự động bằng ML Kit Subject Segmentation, chạy hoàn toàn on-device, không cần internet.

| Màn hình chính | Chọn ảnh | Sau khi xóa nền |
|:-:|:-:|:-:|
| <img width="270" src="https://github.com/user-attachments/assets/a49907ae-5775-4b0d-a6eb-eb4d5ce11b03" /> | <img width="270" src="https://github.com/user-attachments/assets/9fbc34a0-b30b-44c9-801b-2dc2c812b9ee" /> | <img width="270" src="https://github.com/user-attachments/assets/448702aa-e603-4819-82ba-3e6376816b6e" /> |


## Tính năng

- Xóa nền ảnh tự động bằng ML Kit Subject Segmentation
- Xử lý hoàn toàn trên thiết bị (offline, không gửi ảnh lên server)
- Pinch-to-zoom và pan để xem chi tiết
- So sánh ảnh gốc / đã xóa nền bằng nút toggle
- Lưu ảnh PNG với nền trong suốt vào thư viện
- Chọn ảnh từ thư viện hoặc chụp trực tiếp từ camera

## Tech stack

| Package | Vai trò |
|---------|---------|
| `google_mlkit_subject_segmentation` | AI segmentation on-device |
| `image_picker` | Chọn ảnh từ gallery / camera |
| `image` | Xử lý pixel, encode PNG với alpha channel |
| `gal` | Lưu ảnh vào thư viện |

## Yêu cầu

- Android 7.0+ (API 24+)
- Flutter 3.x

## Cài đặt & Build

```bash
git clone https://github.com/dinorin/background_remover.git
cd background_remover
flutter pub get
```

### Debug (chạy trực tiếp trên thiết bị)

```bash
flutter run
```

### Release APK

1. Tạo keystore (chỉ cần làm một lần):

```bash
keytool -genkey -v \
  -keystore android/bgremover.jks \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias bgremover
```

2. Tạo file `android/key.properties`:

```properties
storePassword=<mật khẩu keystore>
keyPassword=<mật khẩu key>
keyAlias=bgremover
storeFile=../bgremover.jks
```

3. Build:

```bash
flutter build apk --release
```

APK output: `build/app/outputs/flutter-apk/app-release.apk`

> **Lưu ý:** Giữ file `bgremover.jks` và `key.properties` cẩn thận — không commit lên git.

## Cấu trúc

```
lib/
├── main.dart
├── pages/
│   └── home_page.dart      # UI + segmentation logic
└── widgets/
    └── checkerboard.dart   # Nền checkerboard cho ảnh transparent
```

**Flow xử lý:**
1. Pick ảnh → `InputImage.fromFilePath`
2. `SubjectSegmenter.processImage` → `foregroundConfidenceMask` (float 0.0–1.0 mỗi pixel)
3. `compute()` isolate — áp mask vào alpha channel từng pixel
4. Encode PNG, hiển thị với `Image.memory`
