# Roblox Studio 연결 방법 (나중에 컴퓨터에서 할 일)

지금은 클라우드에서 만들고 있어서 Studio를 직접 못 켭니다. 대신 **완성된 게임 파일**(`build/StealASlime.rbxl`)을 만들어 두었어요.

## 방법 1 — 가장 쉬움: 파일 열기
1. Roblox Studio 설치: https://create.roblox.com → "Studio 다운로드" → 로그인.
2. GitHub에서 `build/StealASlime.rbxl` 파일을 내려받기.
3. 파일을 더블클릭(또는 Studio에서 File → Open from File).
4. 위쪽 **Play(▶)** 버튼 → 바로 플레이 가능.
5. 출력 창(View → Output)에 `[SelfTest] PASS` 가 보이면 정상.

## 방법 2 — 코드 수정을 Studio에 바로 반영 (Rojo)
1. https://rojo.space 안내대로 Rojo 플러그인을 Studio에 설치.
2. 컴퓨터에 Rojo 설치 후, 이 폴더에서 `rojo serve` 실행.
3. Studio의 Rojo 플러그인에서 **Connect** → 파일을 고치면 Studio에 즉시 반영.

## 방법 3 — AI가 Studio를 직접 조작 (Studio MCP)
로블록스 공식 MCP 서버를 쓰면, 내 컴퓨터의 Claude가 Studio에서 플레이 테스트와 로그 확인까지 할 수 있어요.
1. https://github.com/Roblox/studio-rust-mcp-server 의 안내대로 설치 (설치 프로그램 실행 → Studio 플러그인 자동 설치).
2. 컴퓨터의 Claude(데스크톱 앱 또는 Claude Code)에서 MCP 서버 연결.
3. Claude에게 "Studio에서 플레이 테스트하고 Output 로그 확인해줘"라고 요청.

## 데이터 저장 테스트(선택)
Studio에서 저장을 테스트하려면: Home → **Game Settings → Security → Enable Studio Access to API Services** 켜기.
(게임을 한 번 Publish 해야 켤 수 있어요. 끄고 테스트해도 게임은 정상 작동하며, 저장만 안 됩니다.)
