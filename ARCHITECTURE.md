# Oqim platformasi: xavfsiz arxitektura

## 1-bosqich: mavjud holat va qarorlar

Hozirgi kod bitta HTML ilova va localhost uchun PowerShell/.NET serveridan iborat. Ilova vazifa, qayd, fokus, kutubxona va taqdimotlarni server API’siga yuboradi. Server foydalanuvchini HttpOnly sessiya cookie’sidan aniqlaydi; `/api/data` va `/api/profile` so‘rovlarida mijoz yuborgan `userId` ishlatilmaydi. Akkaunt yaratilganda parol ochiq saqlanmaydi: alohida salt va PBKDF2-SHA256 xeshi ishlatiladi.

Joriy server hisoblarni `%LOCALAPPDATA%\Oqim\accounts.json` faylida saqlaydi va sessiyalarni xotirada yuritadi. Bu bitta lokal ishlab chiqish serveri uchun vaqtinchalik yechim; ko‘p jarayonli yoki ommaviy server uchun mos emas. Sessiya server qayta ishga tushganda tugaydi. Windows PowerShell execution policy `.ps1` bajarilishini hozir bloklayotgani sababli HTTP/API xavfsizlik sinovlari hali bajarilmagan.

Manba fayllar hozir `C:\Users\user\.vscode` ichida, bu odatiy ilova loyihasi papkasi emas. Ishlab chiqarishga tayyorlashdan oldin kodni alohida loyiha/repository papkasiga ko‘chirish kerak.

### Ishonch chegaralari

- Brauzer faqat ko‘rinishni boshqaradi; ruxsatni belgilamaydi.
- Har bir himoyalangan API sessiya cookie’sini tekshiradi va egani sessiyadan oladi.
- Kelajakdagi database yozuvlarida `owner_user_id`/ishtirokchi FK bo‘ladi; so‘rovlar serverda sessiyadagi foydalanuvchi bilan cheklanadi. Mijoz yuborgan ID egani almashtira olmaydi.
- Profilni topish, xabar yuborish, guruhga kirish, kursni boshqarish va virtual xonaga ulanish alohida server qoidalari bilan ruxsat etiladi.
- Hozircha profil va talaba ma’lumotlari xususiy. Hamjamiyatda ko‘rinish faqat aniq opt-in sozlamasi bilan ochiladi.

### Rejalashtirilgan saqlash modeli

Ko‘p foydalanuvchili hostingga o‘tganda PostgreSQL tavsiya etiladi. Asosiy jadvallar: `users`, `profiles`, `sessions`, `tasks`, `library_items`, `presentations`, `conversations`, `conversation_members`, `messages`, `groups`, `group_members`, `courses`, `enrollments`, `lessons`, `materials`, `announcements` va `feedback`. Egaga tegishli jadvallarda foreign key, indeks va server tomonidagi owner filter bo‘ladi; kerak bo‘lsa PostgreSQL Row-Level Security ikkinchi himoya qatlami sifatida qo‘shiladi.

## Bosqichlar va chiqish mezonlari

1. **Arxitektura va xavfsizlik poydevori** — hozirgi server egani sessiyadan aniqlaydi; ro‘yxatdan o‘tish, login, logout, profil va shaxsiy data API’lari bor. Keyingi tekshiruv: anonim so‘rovlar 401, noto‘g‘ri Origin 403, boshqa akkaunt ID’si bilan so‘rov egani o‘zgartira olmasligi. Runtime tekshiruv execution policy ruxsatidan keyin.
2. **Talaba profili** — ism, bio, rang va naqsh faqat profil egasi tomonidan o‘zgartiriladi. Kelajakda avatar/banner yuklashda fayl turi, hajmi va storage ACL tekshiriladi.
3. **Talabalarni qidirish va hamjamiyat** — faqat discoverability’ni yoqqan profillar chiqadi; bloklash va shikoyat qilish qo‘shiladi.
4. **Shaxsiy chat** — o‘qish va yuborish faqat suhbat a’zolariga; server har bir xabarda a’zolikni tekshiradi.
5. **Guruhlar va fan muhokamalari** — a’zolik/rol serverda tekshiriladi; moderator vakolatlari alohida.
6. **Dars yaratish va katalog** — darsni yaratish/tahrirlash faqat instructor egasiga; katalog faqat nashr qilingan darslarni ko‘rsatadi.
7. **Darsga yozilish va virtual auditoriya** — enrollments serverda yaratiladi; xonaga faqat instructor va faol yozilgan talabalar kiradi.
8. **Materiallar, e’lonlar va fikr-mulohazalar** — material ruxsati kurs a’zoligidan meros olinadi; fayllar private storage’da saqlanadi.
9. **Jonli audio/video** — WebRTC uchun LiveKit, Agora yoki shunga o‘xshash xizmat kerak. Server qisqa muddatli, xona/rolga bog‘langan token beradi; API kalit brauzerga berilmaydi.
10. **Yakuniy tekshiruv** — ikki akkauntli izolyatsiya, authorization regression testlari, CSRF/session, mobil, ishlash tezligi, backup va recovery sinovlari.

## Release talablari

Ommaviy chiqarishdan oldin HTTPS, doimiy database, sessiyalarni persistent/revocable saqlash, CSRF himoyasi, login rate limit, parolni tiklash siyosati, audit log, backup va server secret’larini xavfsiz boshqarish kerak. Hozirgi PowerShell JSON serverini internetga to‘g‘ridan-to‘g‘ri chiqarmaslik kerak.