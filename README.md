# BlablaGame

3D RPG в стиле Skyrim на Godot 4.3. Все ассеты процедурные: внешних текстур и
моделей в проекте нет.

## Фаза 3: процедурный мир

| Что | Где |
| --- | --- |
| Рельеф (fbm 4 октавы, раскраска по высоте/наклону) | `shaders/terrain.gdshader` |
| Вода (аналитические волны, Fresnel, цвет по глубине) | `shaders/water.gdshader` |
| Небо (градиент, солнце/луна, облака, звёзды) | `shaders/sky.gdshader` |
| CPU-копия шума для расстановки и коллизии | `scripts/terrain_noise.gd` |
| Расстановка через MultiMeshInstance3D | `scripts/world_generator.gd` |
| Цикл дня/ночи (5 мин = 1 сутки) | `scripts/time_manager.gd` |
| Контроль бюджета производительности | `scripts/main.gd` |

### Главное архитектурное правило

`terrain_height()` продублирован в **трёх** местах: `terrain.gdshader`,
`water.gdshader` и `scripts/terrain_noise.gd`. Шейдер двигает вершины на GPU, а
расстановка пропов и коллизия считаются на CPU — если формулы разъедутся, деревья
повиснут в воздухе, а игрок провалится сквозь землю. Хэш намеренно целочисленный:
это единственная форма, которую GDScript int64 и GLSL uint32 считают одинаково.

Меняешь одну копию — меняй все три. `tests/` это ловит.

### Ограничение 2 ГБ видеопамяти

Запрещено и закреплено в конфиге: SDFGI, Volumetric Fog, SSR, MSAA выше 2x,
больше 3000 MultiMesh-инстансов, больше 4 итераций noise в шейдере.
`scripts/main.gd` проверяет это при старте и пишет нарушения в лог — в том числе
в CI, где stdout сохраняется.

## Проверки

Godot в CI только экспортирует проект, поэтому часть инвариантов проверяется
отдельно (движок для этого не нужен):

```bash
pip install "gdtoolkit==4.*"               # один раз, для проверки синтаксиса
python3 tests/check_noise_parity.py    # CPU/GPU шум совпадают, рельеф валиден
python3 tests/check_world_layout.py    # бюджет инстансов, чанки, ничего не в воде
python3 tests/validate_project.py      # load_steps, ссылки, budget, noise, gdparse
```

`validate_project.py` прогоняет каждый `.gd` через `gdparse` — настоящий парсер
GDScript из Godot 4. Без установленного gdtoolkit он громко пишет `SKIPPED`, а не
делает вид, что всё прошло. Это не паранойя: `gdparse` уже нашёл в
`world_generator.gd` неявную склейку строковых литералов, которую пропустили и
проверка скобок, и **зелёный CI** — `--export-release` вообще не компилирует
GDScript.

Плюс смоук-тест, который реально грузит `main.tscn` и проверяет результат
(коллизия совпадает с `terrain_height()`, игрок не проваливается, 2081 инстанс
на месте, базис солнца ортонормален):

```bash
godot --headless --quit-after 240 res://tests/smoke.tscn
```

Готовый воркфлоу для него лежит в `ci/smoke.yml`, но **не активен**: GitHub App
этой ветки не может создавать файлы в `.github/workflows/` (нет права
`workflows`). Чтобы включить — скопировать `ci/smoke.yml` в
`.github/workflows/smoke.yml`.

`tests/` исключён из экспорта (`exclude_filter` в `export_presets.cfg`), в сборку
игры он не попадает.

## Сборка

GitHub Actions, `.github/workflows/build2.yml`, образ `barichello/godot-ci:4.3`,
артефакт `skyrim-clone-windows`.
