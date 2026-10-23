# 출시 방법 (Steal a Slime [+1 SPEED])

## 1. 열어서 플레이해 보기
1. GitHub에서 `build/StealASlime.rbxl` 파일을 내려받아요.
2. 더블클릭해서 Roblox Studio로 열어요.
3. 위쪽 **Play(▶)** 를 눌러요.
4. View → **Output** 창에 `[SelfTest] ALL PASS` 가 나오면 정상이에요.
   - Studio에서는 결제가 가짜로 처리돼요. 상점 버튼을 눌러도 Robux가 나가지 않고 효과만 확인할 수 있어요.

## 2. 게임 올리기
1. Studio에서 **File → Publish to Roblox** → 새 게임 만들기 → 이름: `Steal a Slime [+1 SPEED]`.
2. **Home → Game Settings**에서 아래 세 가지를 켜거나 고르고 Save를 눌러요.
   - **Security → Enable Studio Access to API Services**: 켜기 (Studio에서도 저장 테스트가 돼요).
   - **Basic Info**: 장르 고르기, 기기에서 **Phone과 Tablet까지 모두 체크**.
   - **Places → 최대 플레이어 수: 8** (기지가 8칸이에요).

## 3. 게임패스와 상품 만들기 (돈 버는 부분)
1. https://create.roblox.com → 내 게임 → **Monetization → Passes** 에서 6개를 만들어요.
   가격은 아래 표대로 해요.
2. **Monetization → Developer Products** 에서 11개를 만들어요.
3. 만든 것마다 **ID 숫자**를 복사해요.
4. 복사한 ID를 `src/shared/Config.luau` 의 `Id = 0` 자리에 넣어요.
   (어렵다면 ID 목록을 Claude에게 붙여넣고 "Config에 넣어줘"라고 하면 돼요.)
5. 다시 빌드한 파일을 Publish 해요.

| 게임패스 | 가격 |
|---|---|
| 2x Coins | 249 |
| 2x Speed | 199 |
| Auto Collect | 99 |
| +2 Incubators | 149 |
| VIP | 299 |
| Lucky | 349 |

| 개발자 상품 | 가격 |
|---|---|
| 100 Gems | 49 |
| 350 Gems | 149 |
| 1,000 Gems | 399 |
| 2,800 Gems | 999 |
| Luck Potion | 79 |
| Speed Potion | 49 |
| Royal Egg | 99 |
| Server Luck | 199 |
| Cash Pack | 49 |
| Big Cash Pack | 149 |
| Instant Hatch | 25 |

## 4. 공개하기
1. Game Settings → **Permissions → Public** 으로 바꾸면 누구나 들어올 수 있어요.
2. 썸네일과 아이콘 이미지를 올리면 사람들이 더 많이 들어와요.
   (화면 디자인과 아이콘은 Studio에 연결된 내 컴퓨터 세션에서 다듬기를 추천해요.)

## 참고
- 뽑기 확률은 게임 안의 Index 창, Royal Egg 구매 화면, 둥지 근처 창에 표시돼요 (로블록스 규정).
- 일부 국가 플레이어에게는 Royal Egg와 행운 상품이 자동으로 숨겨져요 (로블록스 규정).
