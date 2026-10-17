# OQIM

OQIM — talabalar uchun lokal o‘qish yordamchisi prototipi. Vazifalar, kitoblar, fokus, qaydlar va taqdimotlar bitta interfeysda jamlangan.

## Hozirgi holat

### Interfeysda mavjud

- Vazifalar: muddat, qidiruv, bajarilgan holat va filtrlar.
- Kutubxona: Open Library katalogi va shaxsiy javon. Katalog uchun internet kerak.
- Fokus taymeri, shaxsiy qaydlar va slayd muharriri.
- Slayd muharririda bir nechta taqdimot, besh dizayn, slayd tartiblash, ma’ruzachi qaydi, namoyish va chop etish oynasi orqali PDF chiqarish mavjud.
- Kirish/ro‘yxatdan o‘tish interfeysi va profilni bezash boshqaruvlari mavjud.

### Backendda tekshirilgan

- PowerShell API’da ro‘yxatdan o‘tish, login, logout, profil va akkaunt ma’lumotlari endpointlari ishladi.
- Ikki vaqtinchalik akkauntda ma’lumotlar ajratilishi, server qayta ishga tushgach JSON’dan tiklanishi tasdiqlandi.
- Anonim data so‘rovi `401`, boshqa Origin’dan profil o‘zgarishi `403`, boshqa akkauntga tegishli bo‘lmagan faol deck ID’si `400` qaytardi.
- Noto‘g‘ri parol `401`, to‘g‘ri parol login va profil yangilash muvaffaqiyatli bo‘ldi; logoutdan keyin sessiya `401` oldi.
- Sinovlar faqat vaqtinchalik JSON fayl va `8788` portida bajarildi; ishlab chiqarish muhiti tekshirilmagan.

### Hali bajarilmagan

- Hamjamiyat, talabalarni qidirish, shaxsiy/guruhli chat, guruhlar, kurslar, yozilish, virtual auditoriya, kurs materiallari va jonli audio/video yo‘q.
- Firebase SDK, Firebase loyihasi yoki Firebase Security Rules sozlanmagan.
- Parolni tiklash, email tekshiruvi, production hosting va doimiy sessiyalar yo‘q.

## Texnologiyalar va tuzilma

- `index.html` — HTML, CSS va vanilla JavaScript bitta faylda.
- `server.ps1` — Windows PowerShell 5.1 va .NET `HttpListener` asosidagi lokal API/statik server.
- `ARCHITECTURE.md` — ishonch chegaralari va bosqichli reja.
- `.gitignore` — lokal akkaunt ma’lumoti, sirli environment fayllari, log va vaqtinchalik fayllar istisnolari.
- `extensions/` — workspace ichidagi VS Code extension fayllari; OQIM runtime dependency emas.

Hozirgi akkaunt ombori JSON fayl, sessiyalar esa server xotirasida. Bu faqat bitta lokal server uchun prototip; bir nechta server nusxasi yoki ommaviy deploy uchun mos emas.

## Talablar va ishga tushirish

- Windows PowerShell 5.1.
- Mos .NET Framework runtime. Joriy muhitda SHA-256 `Rfc2898DeriveBytes` API mavjud.
- Zamonaviy brauzer.
- Open Library qidiruvi va muqovalari uchun internet.

Node.js, npm, Python, Firebase hisobi yoki maxfiy environment qiymatlari talab qilinmaydi. Bu workspace’da Git CLI va `.git` metadata aniqlanmadi.

PowerShell terminalida loyiha papkasiga o‘tib ishga tushiring:

```powershell
.\server.ps1
```

Keyin `http://localhost:8787/` manzilini oching. `index.html`ni `file://` orqali ochmang; API bir origin’dagi serverni talab qiladi. Port band bo‘lsa:

```powershell
.\server.ps1 -Port 8788
```

`-DataPath` parametridan akkaunt JSON faylining yo‘lini o‘zgartirish uchun foydalaning:

```powershell
.\server.ps1 -Port 8788 -DataPath "$env:LOCALAPPDATA\Oqim\dev-accounts.json"
```

Ushbu ish muhitida `CurrentUser` execution policy `RemoteSigned` qilib sozlangan. Boshqa kompyuterda skript bloklansa, `Get-ExecutionPolicy -List` bilan tekshiring va tashkilot qoidalariga amal qiling; `Bypass` ishlatmang.

## Firebase va environment sozlamalari

Firebase ushbu prototipda ishlatilmaydi: Firebase SDK, project ID, API kalit yoki Firestore qoidalari yo‘q. Hozirgi ilovada environment variable talab qilinmagani uchun `.env.example` kerak emas. Server faqat `-Port` va `-DataPath` parametrlarini qabul qiladi.

Firebase keyinchalik tanlansa, alohida loyiha yarating, admin credential’larni faqat serverda saqlang, Authentication’ni sozlang va Firestore/Storage qoidalarida egasi, guruh a’zoligi, kursga yozilish hamda instructor rolini tekshiring. Xizmat kalitlarini `index.html`ga yoki Git’ga qo‘shmang.

## Xavfsizlik chegaralari

- Default data fayli: `%LOCALAPPDATA%\Oqim\accounts.json`.
- Parollar ochiq matnda saqlanmaydi.
- Himoyalangan API egani cookie’dagi server sessiyasidan oladi; brauzer yuborgan ID egani tanlamaydi.
- Auth/mutating so‘rovlar uchun Origin tekshiruvi mavjud.
- Server localhost va oddiy HTTP’da ishlaydi; sessiyalar xotirada, ombor JSON faylda.
- Bu himoyalar kodda mavjud, ammo serverni ishga tushira olmaganimiz uchun backend security testlari hali o‘tkazilmagan.
- Internetga chiqarmang. Production uchun HTTPS, PostgreSQL yoki mos boshqariladigan baza, qayta chaqiriladigan doimiy sessiyalar, backup, monitoring va alohida authorization testlari kerak.

Hozir database Security Rules yo‘q. Baza tanlanganda har bir jadval/document serverdagi owner yoki membership bilan cheklansin; frontend ko‘rinishi ruxsat nazorati hisoblanmaydi.

## Tekshiruvlar

Bu workspace’da avtomatik test runner yo‘q.

- Windows PowerShell parser: `server.ps1` UTF-8 BOM bilan qayta kodlangach, sintaksis tekshiruvidan o‘tdi.
- HTTP smoke/integration: health, ro‘yxatdan o‘tish, login, cookie `HttpOnly`, noto‘g‘ri parol, logout, profil yangilash, Origin rad etilishi, anonim 401 va ikki akkauntli data isolation tekshirildi.
- Persistence: test serveri qayta ishga tushirilgandan keyin account JSON faylidan login va shaxsiy data tiklandi.
- Brauzer: login/register darvozasi ko‘rinishi va autentifikatsiyasiz asosiy ilovaning yashirinligi tekshirildi.
- PSScriptAnalyzer mavjud bo‘lsa ayrim naming/plaintext-parameter tavsiyalarini bildiradi; API integratsiya sinovi bu tavsiyalarni bartaraf etmaydi.
- Firebase, community, chat, group, course enrollment, classroom va live-media funksiyalari yo‘q; ular uchun test o‘tkazilmadi.
- Chat, guruh, kurs enrollment, virtual classroom va live media funksiyalari hali yo‘qligi sababli ular test qilinmadi.

## Keyingi bosqichlar

1. Serverni ishga tushirib, anonim 401, yaroqsiz Origin, duplicate login va parol tekshiruvlarini sinash.
2. Ikki akkaunt bilan profil va data izolatsiyasini server API orqali isbotlash.
3. Profil tahririni backend bilan amalda tekshirish.
4. Opt-in talabalar katalogi va hamjamiyat.
5. Faqat suhbat a’zolariga ochiq shaxsiy chat.
6. Guruhlar, a’zolik va fan muhokamalari.
7. Instructor egasidagi darslar va katalog.
8. Server tasdiqlaydigan darsga yozilish va virtual auditoriya.
9. Kursga bog‘langan materiallar, e’lonlar va fikr-mulohazalar.
10. WebRTC provayderi (masalan, LiveKit/Agora) tanlansa serverda xona/rol bo‘yicha qisqa muddatli token chiqarish.
11. Production baza, HTTPS, authorization regression, accessibility, mobil, performance, backup va recovery sinovlari.