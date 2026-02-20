# Guruh funksiyalarini yaxshilash - TODO

## Vazifalar ro'yxati

- [x] 1. Reja tasdiqlash
- [x] 2. home_screen.dart - Guruh yaratish formasidan "Members" maydonini olib tashlash
- [x] 3. chat_screen.dart - Guruh nomiga bosganda a'zolar ro'yxatini ko'rsatish
- [x] 4. chat_screen.dart - A'zolar ro'yxatida "A'zo qo'shish" funksiyasi
- [ ] 5. Test qilish

## Tafsilotlar

### 2. home_screen.dart o'zgarishlari ✅
- [x] `_openCreateGroupSheet` metodidan `membersController` ni olib tashlash
- [x] `TextField` (Members) ni olib tashlash
- [x] `createGroup` chaqiruvidan `memberUsernames` ni bo'sh ro'yxat bilan o'tkazish
- [x] `_parseMemberUsernames` metodini olib tashlash (endi kerak emas)

### 3. chat_screen.dart o'zgarishlari ✅
- [x] Guruh sarlavhasiga `GestureDetector` qo'shish - guruh nomiga bosganda a'zolar ochiladi
- [x] Yangi `_showGroupMembersSheet` metodi yaratish
- [x] A'zolar ro'yxatini ko'rsatish (ism, username, role)
- [x] Owner uchun yulduzcha belgisi ko'rsatish

### 4. A'zo qo'shish funksiyasi ✅
- [x] A'zolar ro'yxatida "A'zo qo'shish" tugmasi (faqat owner uchun)
- [x] Mavjud `_showAddGroupMembersSheet` ni integratsiya qilish

## Qilingan o'zgarishlar

### home_screen.dart
- Guruh yaratish formasidan "Members" maydoni olib tashlandi
- Endi guruh yaratishda a'zolarni kiritish shart emas
- A'zolarni keyin guruh ichidan qo'shish mumkin

### chat_screen.dart
- Guruh nomiga bosganda a'zolar ro'yxati ochiladi
- A'zolar ro'yxatida:
  - Profil rasmi
  - Ism
  - Username
  - Role (OWNER/MEMBER)
  - Owner uchun yulduzcha belgisi
- "A'zo qo'shish" tugmasi (faqat owner uchun)
- A'zo qo'shish oynasi alohida ochiladi

