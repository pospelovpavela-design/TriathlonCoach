"""
Workout Planner → iPhone Calendar (.ics)
Генератор тренировочного плана для импорта в Календарь iPhone

Пульсовые зоны Павла:
  Z1: < 119
  Z2: 120–145
  Z3: 146–163
  Z4: 164–175
  Z5: > 176
"""

import uuid
from datetime import datetime, timedelta, timezone
from dataclasses import dataclass, field
from typing import Optional
import json
import os

# ─── Зоны пульса ───────────────────────────────────────────────────────────────

HR_ZONES = {
    "Z1": {"name": "Восстановительная", "min": 0,   "max": 119, "color": "🟢"},
    "Z2": {"name": "Аэробная база",      "min": 120, "max": 145, "color": "🔵"},
    "Z3": {"name": "Аэробный порог",     "min": 146, "max": 163, "color": "🟡"},
    "Z4": {"name": "Анаэробный порог",   "min": 164, "max": 175, "color": "🟠"},
    "Z5": {"name": "Максимум",           "min": 176, "max": 999, "color": "🔴"},
}

# ─── Структуры данных ──────────────────────────────────────────────────────────

@dataclass
class Interval:
    duration_min: int
    zone: str
    note: str = ""

@dataclass
class Workout:
    title: str
    sport: str          # run / bike / swim / strength / rest / mobility
    date: datetime
    duration_min: int
    target_zone: str
    description: str
    intervals: list[Interval] = field(default_factory=list)
    tags: list[str] = field(default_factory=list)
    rpe_target: Optional[int] = None  # 1–10


def zone_info(zone_key: str) -> str:
    z = HR_ZONES[zone_key]
    if z["max"] == 999:
        return f"{z['color']} {zone_key} {z['name']} (>{z['min']} уд/мин)"
    return f"{z['color']} {zone_key} {z['name']} ({z['min']}–{z['max']} уд/мин)"


# ─── Планы тренировок ──────────────────────────────────────────────────────────

def build_pre_shift_week(start_date: datetime) -> list[Workout]:
    """Лёгкая неделя перед вахтой (Пн–Вс)"""
    days = {i: start_date + timedelta(days=i) for i in range(7)}

    workouts = [
        # Понедельник — отдых
        Workout(
            title="🧘 Отдых + мобильность",
            sport="mobility",
            date=days[0].replace(hour=9),
            duration_min=30,
            target_zone="Z1",
            description=(
                "Полный отдых от нагрузки.\n\n"
                "20 мин: лёгкая растяжка всего тела\n"
                "10 мин: МФР (пенный ролик) — квадрицепс, икры, IT-band\n\n"
                "Цель: максимально восстановиться перед отъездом на вахту."
            ),
            tags=["recovery", "pre-shift"],
        ),

        # Вторник — лёгкий бег
        Workout(
            title="🏃 Лёгкий бег Z1",
            sport="run",
            date=days[1].replace(hour=8),
            duration_min=40,
            target_zone="Z1",
            description=(
                f"Лёгкий восстановительный бег.\n\n"
                f"Целевой пульс: {zone_info('Z1')}\n"
                f"Темп: очень комфортный, можно говорить полными предложениями\n\n"
                f"Структура:\n"
                f"  5 мин — разминка шагом/трусцой\n"
                f"  30 мин — лёгкий бег, строго Z1\n"
                f"  5 мин — заминка шагом\n\n"
                f"⚠️ Если пульс уходит выше 119 — перейди на шаг."
            ),
            intervals=[
                Interval(5, "Z1", "Разминка — шаг/трусца"),
                Interval(30, "Z1", "Лёгкий бег Z1 < 119"),
                Interval(5, "Z1", "Заминка — шаг"),
            ],
            rpe_target=4,
            tags=["run", "z1", "pre-shift"],
        ),

        # Среда — вело
        Workout(
            title="🚴 Вело Z1–Z2",
            sport="bike",
            date=days[2].replace(hour=8),
            duration_min=70,
            target_zone="Z2",
            description=(
                f"Аэробная велотренировка — последняя перед вахтой.\n\n"
                f"Целевой пульс: {zone_info('Z1')} / низкий {zone_info('Z2')}\n"
                f"Держи пульс в диапазоне 115–130, максимум 135.\n\n"
                f"Структура:\n"
                f"  10 мин — разминка Z1\n"
                f"  50 мин — ровное усилие, пульс 120–130\n"
                f"  10 мин — заминка Z1\n\n"
                f"💡 Это базовая аэробная работа — никакого ускорения, "
                f"никаких горок в полную силу. Наслаждайся последним выездом на улицу."
            ),
            intervals=[
                Interval(10, "Z1", "Разминка"),
                Interval(50, "Z2", "Аэробная база 120–130 уд/мин"),
                Interval(10, "Z1", "Заминка"),
            ],
            rpe_target=5,
            tags=["bike", "z2", "pre-shift"],
        ),

        # Четверг — лёгкий бег
        Workout(
            title="🏃 Лёгкий бег Z1 (короткий)",
            sport="run",
            date=days[3].replace(hour=8),
            duration_min=35,
            target_zone="Z1",
            description=(
                f"Короткий лёгкий бег — поддержание активности.\n\n"
                f"Целевой пульс: {zone_info('Z1')}\n\n"
                f"Структура:\n"
                f"  5 мин — разминка шагом\n"
                f"  25 мин — лёгкий бег Z1\n"
                f"  5 мин — заминка + растяжка икр и квадрицепса\n\n"
                f"⚠️ Короче среды специально — накапливаем свежесть к отъезду."
            ),
            intervals=[
                Interval(5, "Z1", "Разминка"),
                Interval(25, "Z1", "Лёгкий бег Z1"),
                Interval(5, "Z1", "Заминка + растяжка"),
            ],
            rpe_target=3,
            tags=["run", "z1", "pre-shift"],
        ),

        # Пятница — отдых
        Workout(
            title="🧘 Отдых",
            sport="rest",
            date=days[4].replace(hour=9),
            duration_min=20,
            target_zone="Z1",
            description=(
                "Полный отдых.\n\n"
                "Можно: лёгкая прогулка 20–30 мин без пульсового контроля.\n"
                "Фокус: сборы, питание, сон."
            ),
            tags=["rest", "pre-shift"],
        ),

        # Суббота — по ощущениям
        Workout(
            title="🚶 По ощущениям — прогулка или Z1 бег",
            sport="run",
            date=days[5].replace(hour=9),
            duration_min=40,
            target_zone="Z1",
            description=(
                f"Тренировка по самочувствию.\n\n"
                f"Вариант А (если тело свежее): лёгкий бег 35–40 мин Z1\n"
                f"Вариант Б (если есть усталость): прогулка 45–50 мин\n\n"
                f"Целевой пульс: {zone_info('Z1')}\n\n"
                f"Слушай тело — это последний день перед вахтой."
            ),
            rpe_target=3,
            tags=["run", "optional", "pre-shift"],
        ),

        # Воскресенье — отдых
        Workout(
            title="✈️ Отдых / Отъезд",
            sport="rest",
            date=days[6].replace(hour=9),
            duration_min=15,
            target_zone="Z1",
            description=(
                "Отъезд на вахту.\n\n"
                "Никаких тренировок. Максимум — растяжка 15 мин утром.\n"
                "Приоритет: хорошо поесть, выспаться в дороге."
            ),
            tags=["rest", "travel"],
        ),
    ]
    return workouts


def build_shift_week_template(start_date: datetime, week_num: int = 1) -> list[Workout]:
    """Шаблон недели на вахте"""
    days = {i: start_date + timedelta(days=i) for i in range(7)}

    workouts = [
        Workout(
            title=f"🏋️ Силовая — Ноги + кор (Вахта W{week_num})",
            sport="strength",
            date=days[0].replace(hour=18),
            duration_min=60,
            target_zone="Z2",
            description=(
                "Силовая тренировка — акцент ноги и кор.\n\n"
                "Разминка: 10 мин велостанок или орбитрек Z1\n\n"
                "Основная часть (3 подхода × 10 повторений):\n"
                "  • Приседания со штангой\n"
                "  • Румынская тяга\n"
                "  • Выпады с гантелями (по 10 на ногу)\n"
                "  • Подъёмы на носки стоя\n"
                "  • Планка 3 × 45 сек\n"
                "  • Подъём ног в висе 3 × 12\n\n"
                "Пульс во время силовой: до 145 (Z2) — это норма.\n"
                f"Отдых между подходами: 90 сек."
            ),
            tags=["strength", "legs", "core", "shift"],
        ),

        Workout(
            title=f"🚴 Велостанок Z1–Z2 (Вахта W{week_num})",
            sport="bike",
            date=days[1].replace(hour=18),
            duration_min=55,
            target_zone="Z2",
            description=(
                f"Аэробная работа на велостанке.\n\n"
                f"Целевой пульс: {zone_info('Z1')} / {zone_info('Z2')}\n"
                f"Держи пульс 115–130 уд/мин.\n\n"
                f"Структура:\n"
                f"  10 мин — разминка Z1\n"
                f"  35 мин — равномерно Z2 (120–130)\n"
                f"  10 мин — заминка Z1\n\n"
                f"💡 Фильм или подкаст — отличная компания."
            ),
            intervals=[
                Interval(10, "Z1", "Разминка"),
                Interval(35, "Z2", "Аэробная база 120–130"),
                Interval(10, "Z1", "Заминка"),
            ],
            rpe_target=5,
            tags=["bike", "z2", "shift"],
        ),

        Workout(
            title=f"🏋️ Силовая — Верх + кор (Вахта W{week_num})",
            sport="strength",
            date=days[2].replace(hour=18),
            duration_min=60,
            target_zone="Z2",
            description=(
                "Силовая тренировка — верх тела и кор.\n\n"
                "Разминка: 10 мин гребной тренажёр лёгко\n\n"
                "Основная часть (3 × 10):\n"
                "  • Жим штанги лёжа\n"
                "  • Тяга штанги в наклоне\n"
                "  • Жим гантелей сидя (плечи)\n"
                "  • Подтягивания или тяга блока\n"
                "  • Отжимания на брусьях\n"
                "  • Скручивания на пресс 3 × 15\n\n"
                "Заминка: 5 мин растяжка грудь/спина."
            ),
            tags=["strength", "upper", "core", "shift"],
        ),

        Workout(
            title=f"🚶 Беговая дорожка — ходьба с наклоном (Вахта W{week_num})",
            sport="run",
            date=days[3].replace(hour=18),
            duration_min=50,
            target_zone="Z1",
            description=(
                f"Кардио без ударной нагрузки — ходьба на наклоне.\n\n"
                f"Целевой пульс: {zone_info('Z1')}\n\n"
                f"Настройки дорожки:\n"
                f"  Наклон: 8–12°\n"
                f"  Скорость: подбери так, чтобы пульс держался 110–118\n\n"
                f"Структура:\n"
                f"  5 мин — плоская дорожка, разминка\n"
                f"  40 мин — ходьба на наклоне 10°\n"
                f"  5 мин — плоская, заминка\n\n"
                f"💡 Ходьба на наклоне = аэробная нагрузка + 0 ударов на суставы. "
                f"Для поддержания беговых мышц идеально."
            ),
            intervals=[
                Interval(5, "Z1", "Разминка — плоская дорожка"),
                Interval(40, "Z1", "Ходьба наклон 10° — пульс 110–118"),
                Interval(5, "Z1", "Заминка"),
            ],
            rpe_target=4,
            tags=["run", "z1", "treadmill", "shift"],
        ),

        Workout(
            title=f"🏋️ Силовая — Полное тело (Вахта W{week_num})",
            sport="strength",
            date=days[4].replace(hour=18),
            duration_min=55,
            target_zone="Z2",
            description=(
                "Комплексная силовая — всё тело, суперсеты.\n\n"
                "Формат: суперсеты (2 упражнения без отдыха, потом 90 сек пауза)\n\n"
                "Суперсет A (3 × 10):\n"
                "  A1: Приседания\n"
                "  A2: Жим гантелей лёжа\n\n"
                "Суперсет B (3 × 10):\n"
                "  B1: Тяга штанги в наклоне\n"
                "  B2: Выпады\n\n"
                "Суперсет C (3 × 12):\n"
                "  C1: Разгибания ног в тренажёре\n"
                "  C2: Сгибания рук с гантелями\n\n"
                "Финиш: планка 3 × 1 мин"
            ),
            tags=["strength", "full-body", "shift"],
        ),

        Workout(
            title=f"🎯 Смешанное кардио Z1 (Вахта W{week_num})",
            sport="bike",
            date=days[5].replace(hour=18),
            duration_min=55,
            target_zone="Z1",
            description=(
                f"Лёгкое смешанное кардио — 3 снаряда.\n\n"
                f"Целевой пульс: строго {zone_info('Z1')}\n\n"
                f"20 мин — велостанок (115–118 уд/мин)\n"
                f"20 мин — гребной тренажёр (лёгкий темп)\n"
                f"15 мин — эллипс\n\n"
                f"Без остановок между снарядами. Темп разговорный."
            ),
            intervals=[
                Interval(20, "Z1", "Велостанок"),
                Interval(20, "Z1", "Гребной тренажёр"),
                Interval(15, "Z1", "Эллипс"),
            ],
            rpe_target=4,
            tags=["cardio", "mixed", "z1", "shift"],
        ),

        Workout(
            title=f"🧘 Восстановление + мобильность (Вахта W{week_num})",
            sport="mobility",
            date=days[6].replace(hour=10),
            duration_min=30,
            target_zone="Z1",
            description=(
                "Полное восстановление.\n\n"
                "10 мин — МФР (пенный ролик или мяч)\n"
                "  Акцент: квадрицепс, ягодичные, IT-band, икры\n\n"
                "20 мин — растяжка:\n"
                "  • Голубь (по 2 мин на сторону)\n"
                "  • Растяжка сгибателей бедра\n"
                "  • Растяжка грудных\n"
                "  • Скручивания лёжа\n\n"
                "Опционально: 20–30 мин спокойной прогулки."
            ),
            tags=["recovery", "mobility", "shift"],
        ),
    ]
    return workouts


# ─── Генератор .ics ────────────────────────────────────────────────────────────

def escape_ics(text: str) -> str:
    """Экранируем спецсимволы для формата iCalendar"""
    text = text.replace("\\", "\\\\")
    text = text.replace(";", "\\;")
    text = text.replace(",", "\\,")
    text = text.replace("\n", "\\n")
    return text


def workout_to_ics_event(workout: Workout) -> str:
    uid = str(uuid.uuid4())
    now = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")

    dtstart = workout.date.strftime("%Y%m%dT%H%M%S")
    dtend = (workout.date + timedelta(minutes=workout.duration_min)).strftime("%Y%m%dT%H%M%S")

    # Собираем полное описание
    desc_parts = [workout.description]
    if workout.intervals:
        desc_parts.append("\n── СТРУКТУРА ──")
        for i, interval in enumerate(workout.intervals, 1):
            z = HR_ZONES[interval.zone]
            hr_str = f">{z['min']}" if z['max'] == 999 else f"{z['min']}–{z['max']}"
            desc_parts.append(f"{i}. {interval.duration_min} мин | {interval.zone} | {hr_str} уд/мин | {interval.note}")

    if workout.rpe_target:
        desc_parts.append(f"\n🎯 Субъективная нагрузка (RPE): {workout.rpe_target}/10")

    if workout.tags:
        desc_parts.append(f"🏷 Теги: {', '.join(workout.tags)}")

    full_desc = "\n".join(desc_parts)

    # Цвет категории по спорту
    category_map = {
        "run": "SPORT",
        "bike": "SPORT",
        "swim": "SPORT",
        "strength": "PERSONAL",
        "rest": "PERSONAL",
        "mobility": "PERSONAL",
    }
    category = category_map.get(workout.sport, "PERSONAL")

    event = (
        f"BEGIN:VEVENT\n"
        f"UID:{uid}\n"
        f"DTSTAMP:{now}\n"
        f"DTSTART;TZID=Asia/Irkutsk:{dtstart}\n"
        f"DTEND;TZID=Asia/Irkutsk:{dtend}\n"
        f"SUMMARY:{escape_ics(workout.title)}\n"
        f"DESCRIPTION:{escape_ics(full_desc)}\n"
        f"CATEGORIES:{category}\n"
        f"STATUS:CONFIRMED\n"
        f"END:VEVENT\n"
    )
    return event


def workouts_to_ics(workouts: list[Workout], calendar_name: str) -> str:
    header = (
        "BEGIN:VCALENDAR\n"
        "VERSION:2.0\n"
        "PRODID:-//Triathlon Planner//RU\n"
        f"X-WR-CALNAME:{calendar_name}\n"
        "X-WR-TIMEZONE:Asia/Irkutsk\n"
        "CALSCALE:GREGORIAN\n"
        "METHOD:PUBLISH\n"
    )
    footer = "END:VCALENDAR\n"
    events = "".join(workout_to_ics_event(w) for w in workouts)
    return header + events + footer


# ─── Экспорт JSON (для будущего анализа) ──────────────────────────────────────

def workouts_to_json(workouts: list[Workout]) -> str:
    data = []
    for w in workouts:
        data.append({
            "title": w.title,
            "sport": w.sport,
            "date": w.date.isoformat(),
            "duration_min": w.duration_min,
            "target_zone": w.target_zone,
            "description": w.description,
            "intervals": [
                {"duration_min": i.duration_min, "zone": i.zone, "note": i.note}
                for i in w.intervals
            ],
            "tags": w.tags,
            "rpe_target": w.rpe_target,
            "planned": True,
            "completed": False,
            "actual_avg_hr": None,
            "actual_duration_min": None,
            "notes_after": "",
        })
    return json.dumps(data, ensure_ascii=False, indent=2)


# ─── Главная функция ───────────────────────────────────────────────────────────

def main():
    output_dir = "/mnt/user-data/outputs"
    os.makedirs(output_dir, exist_ok=True)

    # Начало предвахтовой недели — ближайший понедельник
    today = datetime.now()
    days_to_monday = (7 - today.weekday()) % 7
    if days_to_monday == 0:
        days_to_monday = 0
    next_monday = (today + timedelta(days=days_to_monday)).replace(
        hour=0, minute=0, second=0, microsecond=0
    )

    print(f"📅 Предвахтовая неделя начинается: {next_monday.strftime('%d.%m.%Y (%A)')}")

    # 1. Предвахтовая неделя
    pre_shift = build_pre_shift_week(next_monday)
    ics_pre = workouts_to_ics(pre_shift, "🏃 Тренировки — Предвахта")
    json_pre = workouts_to_json(pre_shift)

    pre_ics_path = f"{output_dir}/pre_shift_week.ics"
    pre_json_path = f"{output_dir}/pre_shift_week.json"

    with open(pre_ics_path, "w", encoding="utf-8") as f:
        f.write(ics_pre)
    with open(pre_json_path, "w", encoding="utf-8") as f:
        f.write(json_pre)

    print(f"✅ Предвахта ICS: {pre_ics_path}")
    print(f"✅ Предвахта JSON: {pre_json_path}")

    # 2. Первая неделя на вахте (шаблон)
    shift_start = next_monday + timedelta(days=10)  # ~через 1.5 недели
    shift_w1 = build_shift_week_template(shift_start, week_num=1)
    ics_shift = workouts_to_ics(shift_w1, "🏋️ Тренировки — Вахта")
    json_shift = workouts_to_json(shift_w1)

    shift_ics_path = f"{output_dir}/shift_week1.ics"
    shift_json_path = f"{output_dir}/shift_week1.json"

    with open(shift_ics_path, "w", encoding="utf-8") as f:
        f.write(ics_shift)
    with open(shift_json_path, "w", encoding="utf-8") as f:
        f.write(json_shift)

    print(f"✅ Вахта W1 ICS: {shift_ics_path}")
    print(f"✅ Вахта W1 JSON: {shift_json_path}")

    # Сводка
    print("\n═══════════════════════════════════════")
    print("📋 ПРЕДВАХТОВАЯ НЕДЕЛЯ:")
    for w in pre_shift:
        print(f"  {w.date.strftime('%a %d.%m')} — {w.title} ({w.duration_min} мин)")

    print("\n📋 ВАХТА — НЕДЕЛЯ 1 (шаблон):")
    for w in shift_w1:
        print(f"  {w.date.strftime('%a %d.%m')} — {w.title} ({w.duration_min} мин)")

    print("\n═══════════════════════════════════════")
    print("✅ Готово! Импортируй .ics файлы в Календарь iPhone:")
    print("   1. Открой файл .ics на iPhone (через Файлы / AirDrop / почту)")
    print("   2. Нажми 'Добавить все' → выбери нужный календарь")
    print("   3. Каждая тренировка появится как событие с полным описанием")


if __name__ == "__main__":
    main()
