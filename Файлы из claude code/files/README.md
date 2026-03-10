# TriathlonCoach — iOS App
## Автоматическое добавление тренировок на Apple Watch

### Что делает приложение
1. Читает JSON-файлы из `workout_planner.py`
2. Отображает недельный план с пульсовыми зонами
3. **Одной кнопкой добавляет тренировку на Apple Watch** через WorkoutKit
4. На часах видишь каждый отрезок, целевой пульс, и получаешь вибрацию при выходе из зоны

---

### Требования
- Mac с Xcode 15+
- iPhone с iOS 17+
- Apple Watch с watchOS 10+
- Бесплатный Apple ID (для установки на свой телефон)

---

### Настройка Xcode (15 минут один раз)

#### 1. Создай новый проект
```
Xcode → File → New → Project
iOS → App
Product Name: TriathlonCoach
Interface: SwiftUI
Language: Swift
```

#### 2. Скопируй файлы
Перетащи все `.swift` файлы из этой папки в проект Xcode:
- `TriathlonCoachApp.swift`
- `Models.swift`
- `WorkoutKitManager.swift`
- `WorkoutLoader.swift`
- `ContentView.swift`
- `WorkoutRow.swift`
- `WorkoutDetailView.swift`

Замени `Info.plist` содержимым из `Info.plist` этой папки.

#### 3. Добавь WorkoutKit framework
```
Project → Target → General → Frameworks, Libraries, and Embedded Content
→ "+" → WorkoutKit
```

#### 4. Включи HealthKit Capability
```
Project → Target → Signing & Capabilities
→ "+ Capability" → HealthKit
✓ поставь галку "Clinical Health Records" — НЕТ
✓ поставь галку "Background Delivery" — НЕТ
Нужно только базовое HealthKit
```

#### 5. Укажи свой Team
```
Project → Target → Signing & Capabilities
Team: [выбери свой Apple ID]
Bundle Identifier: com.ТВОЕИМЯ.TriathlonCoach
```

#### 6. Запусти на iPhone
Подключи iPhone → выбери его как destination → Cmd+R

---

### Передача JSON-файлов на iPhone

После генерации плана в `workout_planner.py`:

**Вариант А — AirDrop (быстрее всего)**
```bash
# На Mac:
open /mnt/user-data/outputs/  # или где лежат файлы
# Правый клик на pre_shift_week.json → Поделиться → AirDrop → твой iPhone
# На iPhone: сохранить в Files → В приложении жмёшь "↓" (импорт)
```

**Вариант Б — iCloud Drive**
```bash
cp pre_shift_week.json ~/Library/Mobile\ Documents/com~apple~CloudDocs/
cp shift_week1.json ~/Library/Mobile\ Documents/com~apple~CloudDocs/
# Файлы автоматически появятся в Files на iPhone
```

**Вариант В — прямо в Documents приложения**
```bash
# Xcode → Window → Devices and Simulators → твой iPhone
# Выбери TriathlonCoach → Download Container → скопируй JSON в Documents
```

---

### Как работает на часах

После нажатия "Добавить на Apple Watch":

1. Открой **приложение Тренировка** на Apple Watch
2. Листай вниз до **"Собственная тренировка"** → найди название тренировки
3. Нажми — и видишь каждый отрезок:
   - Название отрезка ("Аэробная база 120–130")
   - Целевой пульс
   - Таймер обратного отсчёта
4. **Часы вибрируют** когда пульс выходит из целевой зоны

---

### Полная схема системы

```
workout_planner.py
    ↓ генерирует
pre_shift_week.json / shift_week1.json
    ↓ импорт в приложение
TriathlonCoach iOS App
    ↓ WorkoutKit API
Apple Watch → Workout App
    ↓ после тренировки
Apple Health export.zip
    ↓ (следующий шаг)
Анализатор: план vs факт
```

---

### Пульсовые зоны в приложении
| Зона | Диапазон | Значение |
|------|----------|---------|
| Z1 | < 119 | Восстановительная |
| Z2 | 120–145 | Аэробная база |
| Z3 | 146–163 | Аэробный порог |
| Z4 | 164–175 | Анаэробный порог |
| Z5 | > 176 | Максимум |
