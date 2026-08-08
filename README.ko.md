# FreePlayer (Android)

로컬 음악 플레이어. 네트워크 없음, 로그인 없음, 데이터 수집 없음. 음악은 당신의 기기에, 당신만의 폴더 구조로.

> macOS(SwiftUI) 구현은 저장소 `Swift` 브랜치에, 이전 웹 버전은 `master`에 있습니다.

## 지원 형식

MP3, FLAC, WAV, OGG, M4A, AAC, OPUS, MP4(시스템 디코더 지원 범위)

## 주요 기능

- **가져오기 및 공유**: 시스템 파일 선택기로 폴더 가져오기; 다른 앱(위챗, 파일 관리자 등)에서 공유한 오디오는 "FreePlayer로 열기"로 원탭 가져오기
- **라이브러리 관리**: 메타데이터 자동 추출(제목, 아티스트, 앨범, 연도, 장르, 트랙 번호, 비트레이트, 샘플레이트, 채널 수), 아티스트/앨범 구조로 저장, 내장 커버 추출
- **재생 통계**: 재생마다 기록(시작/종료, 재생 시간, 재생 비율), 총 시간·재생 횟수·Top10 곡/아티스트·최근 30일 일별 통계
- **재생 목록**: 생성/이름 변경/삭제, 단일/일괄 추가, 곡 목록 편집
- **LRC 가사**: .lrc 자동 감지 또는 수동 연결, 인코딩 폴백 UTF-8 → GB18030 → Shift_JIS
- **ReplayGain**: 재생 볼륨 자동 조절
- **시각화**: 오실로스코프 + 스펙트럼 + 스펙트로그램 워터폴 3가지 모드
- **몰입 모드**: 전체 화면 방해 없는 재생 화면
- **미디어 키/알림**: 포그라운드 서비스 알림으로 재생 제어, 잠금 화면/블루투스 이어폰 지원

## 빌드

Android SDK 필요(compileSdk 37, minSdk 26).

```bash
cd Android
./gradlew :app:assembleDebug     # 디버그 APK
./gradlew :app:assembleRelease   # 릴리스 APK(서명 설정 필요)
./gradlew :app:testDebugUnitTest # 단위 테스트
```

릴리스 서명: `freeplayer-release.jks`와 `keystore.properties`(storeFile/storePassword/keyAlias/keyPassword)를 `Android/`에 배치. 이 파일은 git에서 무시되어 커밋되지 않습니다.

## 데이터베이스

SQLite, 앱 전용 데이터 디렉터리 내:

- tracks — 곡(재생 이득, lrc_path 등)
- play_history — 재생 기록
- playlists / playlist_tracks — 재생 목록과 곡
- settings — 키-값 설정

## 라이선스

GPL v3. LICENSE 참조.

---

## Language / 语言

[English](README.en.md) · [简体中文](README.md) · [繁體中文](README.zh-TW.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [Français](README.fr.md) · [Deutsch](README.de.md) · [Español](README.es.md) · [Português](README.pt.md) · [Русский](README.ru.md) · [Italiano](README.it.md) · [العربية](README.ar.md) · [हिन्दी](README.hi.md)
