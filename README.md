# Background Remover

Flutter app xóa nền ảnh tự động bằng ML Kit Subject Segmentation, chạy hoàn toàn on-device, không cần internet.

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

## Cài đặt

```bash
git clone https://github.com/dinorin/background_remover.git
cd background_remover
flutter pub get
flutter run
```

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
