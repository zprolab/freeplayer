# FreePlayer (macOS)

로컬 음악 플레이어. 네트워크 없음, 로그인 없음, 데이터 수집 없음. 음악은 당신의 하드 디스크에, 당신만의 폴더 구조로.

네이티브 macOS(SwiftUI + AppKit) 구현. 타사 런타임 의존성 없음(시스템 프레임워크 + SQLite만).

## 지원 형식

MP3, FLAC, WAV, OGG, M4A, AAC, AIFF(AVFoundation 디코딩 가능 형식)

## 주요 기능

- **가져오기 및 라이브러리 관리**: 가져올 때 메타데이터 자동 추출(제목, 아티스트, 앨범, 연도, 장르, 트랙 번호, 비트레이트, 샘플레이트, 채널 수). 아티스트/앨범 구조로 복사 또는 심볼릭 링크(설정에서 선택)
- **재생 통계**: 재생 세션을 SQLite에 기록(시작/종료, 재생 시간, 재생 비율). 총 시간, 재생 횟수, Top10 곡/아티스트, 최근 30일 일별 통계
- **재생 목록**: 생성/이름 변경/삭제, 단일/일괄 추가, 곡 목록 편집
- **LRC 가사**: .lrc 자동 감지 또는 수동 연결. 인코딩 폴백 UTF-8 → GB18030 → Shift_JIS
- **ReplayGain**: 파일 태그로 재생 볼륨 자동 조절
- **커버**: 가져올 때 내장 아트워크를 추출해 앨범의 .covers 폴더에 저장
- **미디어 키 / 트레이**: 시스템 재생/일시정지·이전·다음 키, Control Center 곡 정보, 메뉴바 트레이로 재생 제어. 창을 닫으면 트레이로 숨기고 계속 재생
- **시각화**: 실시간 파형(오실로스코프 + 스펙트럼) 또는 스펙트로그램 워터폴
- **몰입 모드**: 전체 화면 방해 없는 재생. 노래방 가사와 글꼴 크기 조절 지원

## 빌드(macOS 13+, Xcode CLT / Swift 6 필요)

```bash
cd macos
make            # release 빌드 + FreePlayer.app 패키징
make run        # 디버그 빌드 직접 실행
make run-app    # 패키징된 앱 열기
make test       # 유닛 테스트 실행
```

## 데이터베이스

SQLite, ~/Library/Application Support/FreePlayer/library.db:

- tracks — 곡(replaygain, play_count, last_played_at, lrc_path 등)
- play_history — 재생 기록
- playlists / playlist_tracks — 재생 목록과 곡
- settings — 키-값 설정

## 라이선스

GPL v3. LICENSE 참조.

---

## Language / 语言

[English](README.en.md) · [简体中文](README.md) · [繁體中文](README.zh-TW.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [Français](README.fr.md) · [Deutsch](README.de.md) · [Español](README.es.md) · [Português](README.pt.md) · [Русский](README.ru.md) · [Italiano](README.it.md) · [العربية](README.ar.md) · [हिन्दी](README.hi.md)
