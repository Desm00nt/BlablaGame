class_name StoryData
extends RefCounted

## "Пепельная Корона" - story database for Act I ("Пепел").
##
## Everything is data-driven so the quest manager, dialogue UI and echo
## visions stay dumb runners. Text is authored in Russian; keys are ASCII.
##
## Quest shape:
##   QUESTS[id] = {title, stages: [{objective, marker, journal, counter?}]}
##   counter = {tag, need} - kill objective, formatted into the tracker.
##
## Dialogue shape:
##   DIALOGUES[id] = {npc, steps: [step, ...], effects: [...]}
##   step line   = {type: "line", speaker?, text}
##   step choice = {type: "choice", prompt, options: [{text, goto?, effects?}]}
##   effects run when the dialogue reaches its end (or a chosen option).
##
## Echo shape:
##   ECHOES[id] = {lines: [{text, dur, speaker?}], ghosts: [...], effects}
##   ghost = {palette, from: Vector3, to: Vector3, delay, dur} (echo-local XZ,
##   Y is resolved from terrain at spawn).
##
## All effects are dicts applied by QuestManager.run_effects():
##   {advance_quest: id} {start_quest: id} {complete_quest: id}
##   {give_item: id} {show_symbol: true} {chapter_end: n}

const MARKER_CAMPFIRE := "campfire"
const MARKER_VILLAGE := "village"
const MARKER_BARROW := "barrow"
const MARKER_BARROW_STONE := "barrow_stone"

const QUESTS := {
	"ash": {
		"title": "Пепел",
		"chapter": "Глава I",
		"stages": [
			{
				"objective": "Осмотреться среди пепла",
				"marker": MARKER_CAMPFIRE,
				"journal": "Караван разгромлен, все мертвы. Я жив — и не понимаю почему. На руке тлеет символ, которого вчера не было. Осмотрю лагерь.",
			},
			{
				"objective": "Дойти до стоянки Каменный Брод",
				"marker": MARKER_VILLAGE,
				"journal": "Мёртвые не тронули меня. Их хозяин почему-то этого хотел. Тракт ведёт на юго-восток — там стоянка Каменный Брод.",
			},
		],
	},
	"barrow": {
		"title": "Голос в кургане",
		"chapter": "Глава I",
		"stages": [
			{
				"objective": "Пробиться к чёрному камню кургана Аш-Вейл",
				"marker": MARKER_BARROW,
				"counter": {"tag": "barrow_draugr", "need": 3},
				"journal": "Ингвар рассказал: у кургана Аш-Вейл пропали паломники. Если там Пустые — я узнаю, что будит мёртвых.",
			},
			{
				"objective": "Прикоснуться к памяти чёрного камня",
				"marker": MARKER_BARROW_STONE,
				"journal": "Курган зачищен. Чёрный камень у входа гудит, как улей. Коснусь — и посмотрю, что он помнит.",
			},
			{
				"objective": "Вернуться к Ингвару в Каменный Брод",
				"marker": MARKER_VILLAGE,
				"journal": "Осколок Пепельной Короны. Он у меня внутри — потому Пустые и не тронули. Ингвар должен это услышать.",
			},
		],
	},
}

const DIALOGUES := {
	"ingvar_1": {
		"npc": "Ингвар Мудрый",
		"steps": [
			{"type": "line", "text": "Живой? Клянусь пеплом, я думал, что хороню тебя вместе с остальными. Ты лежал среди мёртвых, и Пустые прошли мимо — как мимо надгробия."},
			{"type": "line", "text": "Меня зовут Ингвар. Когда-то я был сказителем при ярле, теперь грею путников у этого костра. Садись, если ноги держат."},
			{"type": "choice", "prompt": "Что ты знаешь о нападавших?",
				"options": [
					{"text": "«Их были десятки. Они не рычали — они молчали.»", "goto": 3},
					{"text": "«Мне нужно знать, кто я теперь такой.»", "goto": 4},
				]},
			{"type": "line", "text": "Молчали — значит, были Пустыми. Мертвецы из старых курганов. Три сотни лет спали, а в этот месяц встали разом. Сказители винят ярлов, ярлы винят регента, регент винит всех сразу."},
			{"type": "line", "text": "Пустые не молчат. Они не дышат, потому им нечем молчать. А мимо тебя прошли... Значит, ты для них — пустое место. Или не пустое."},
			{"type": "choice", "prompt": "Покажи руку. Символ тлеет, как угли.",
				"options": [
					{"text": "«Что это за печать?»", "goto": 6},
				]},
			{"type": "line", "text": "Такой знак я видел однажды — на двери кургана Аш-Вейл, на севере. Жрец запрещал его касаться и говорил: «Это замок»."},
			{"type": "line", "text": "Сходи туда, раз ноги держат. Паломники ушли к кургану три дня назад и не вернулись. Если Пустые будятся — след рядом. А я подниму людей."},
			{"type": "line", "text": "И вот ещё, путник: не говори о символе никому. В Эйргарде снова горят костры — на этот раз Орден Рассвета складывает в них магов."},
		],
		"effects": [{"complete_quest": "ash"}, {"start_quest": "barrow"}],
	},
	"ingvar_2": {
		"npc": "Ингвар Мудрый",
		"steps": [
			{"type": "line", "text": "Клянусь... Это же осколок Короны. Настоящей. Я думал, это сказка для тинга, — а он тёплый, как чужая ладонь."},
			{"type": "choice", "prompt": "Ингвар смотрит на осколок так, будто тот смотрит в ответ.",
				"options": [
					{"text": "«Корона не будила мёртвых. Она их держала.»", "goto": 2},
					{"text": "«Пустые звали меня хозяином, Ингвар.»", "goto": 3},
				]},
			{"type": "line", "text": "Семь замков... Старая песня играла иначе: «семь побед над тьмой». Кто-то переписал слова, чтобы мёртвые остались врагами. Пойми: людям выгодно воевать с мёртвыми — живым тогда не с кем."},
			{"type": "line", "text": "Звали... хозяином. Значит, легенда врала с первого слова: древний король не правил мёртвыми — он заключил договор с тем, что под курганами. И часть договора теперь в твоей груди."},
			{"type": "line", "text": "Слушай внимательно. За Корону уже идут трое: ярлы Севера, регент и Орден Рассвета. Орден собирает осколки — и тех, кто осколки носит, складывает в костры."},
			{"type": "line", "text": "Пока ты для них никто. Останешься никем — проживёшь дольше. Иди в мир, наберись сил. Когда за тобой придут — а они придут, — возвращайся ко мне."},
			{"type": "line", "text": "Дальше — дорога. Моя сказка кончилась, твоя только начинается, хранитель."},
		],
		"effects": [{"complete_quest": "barrow"}, {"chapter_end": 1}],
	},
}

const ECHOES := {
	"campfire": {
		"lines": [
			{"text": "Эхо... костёр ещё горел, когда всё началось.", "dur": 3.0, "speaker": ""},
			{"text": "— Свет! Уводи телегу на восток, к броду!", "dur": 3.0, "speaker": "Бьёрн, караванщик"},
			{"text": "Скрежет стали. Тишина. Такой тишины не бывает у живых.", "dur": 3.2, "speaker": ""},
			{"text": "— Он ещё дышит. Хозяин велел его не трогать.", "dur": 3.2, "speaker": "Женский голос"},
			{"text": "— Печать поставлена. Теперь ты — часть договора, странник.", "dur": 3.4, "speaker": "Женский голос"},
		],
		"ghosts": [
			{"palette": "draugr", "from": Vector3(-1.0, 0.0, -9.0), "to": Vector3(-1.0, 0.0, 6.0), "delay": 0.4, "dur": 5.5},
			{"palette": "draugr", "from": Vector3(2.2, 0.0, -10.0), "to": Vector3(2.2, 0.0, 5.0), "delay": 1.6, "dur": 6.5},
			{"palette": "dawn", "from": Vector3(-0.6, 0.0, -1.8), "to": Vector3(-0.6, 0.0, -1.8), "delay": 8.5, "dur": 6.0},
		],
		"effects": [{"advance_quest": "ash"}, {"show_symbol": true}],
	},
	"barrow_stone": {
		"lines": [
			{"text": "Камень помнит холод сильнее, чем огонь.", "dur": 3.0, "speaker": ""},
			{"text": "— Семь замков, семь клятв. Пока они в горах — Он спит.", "dur": 3.2, "speaker": "Жрец в сером"},
			{"text": "— Народ не должен знать, что мы не победили смерть. Мы её подкупили.", "dur": 3.4, "speaker": "Древний король"},
			{"text": "— Один осколок я унёс в себя, чтобы замок не сломался врасплох. Если читаешь это эхо — замок дрожит.", "dur": 3.6, "speaker": "Древний король"},
			{"text": "Осколок ложится тебе в ладонь — тёплый, как чужая рука.", "dur": 3.0, "speaker": ""},
		],
		"ghosts": [
			{"palette": "king", "from": Vector3(-0.8, 0.0, -1.6), "to": Vector3(-0.8, 0.0, -1.6), "delay": 0.8, "dur": 8.0},
			{"palette": "priest", "from": Vector3(0.9, 0.0, -1.2), "to": Vector3(0.9, 0.0, -1.2), "delay": 1.2, "dur": 8.0},
		],
		"effects": [{"advance_quest": "barrow"}, {"give_item": "ashen_shard"}],
	},
}

## Ghost palettes for echo visions. alpha < 1 turns every material of the rig
## translucent and lets a little cold emission through.
const GHOST_PALETTES := {
	"draugr": {
		"tunic": Color(0.30, 0.33, 0.27), "armor": Color(0.42, 0.36, 0.30),
		"skin": Color(0.62, 0.66, 0.58), "leather": Color(0.20, 0.18, 0.14),
		"cape": Color(0.16, 0.2, 0.16), "eyes": Color(0.25, 1.0, 0.35),
		"emissive": true, "alpha": 0.55,
	},
	"dawn": {
		"tunic": Color(0.88, 0.86, 0.78), "armor": Color(0.92, 0.80, 0.45),
		"skin": Color(0.87, 0.68, 0.52), "leather": Color(0.55, 0.45, 0.30),
		"cape": Color(0.90, 0.82, 0.55), "eyes": Color(0.95, 0.85, 0.30),
		"emissive": false, "alpha": 0.62,
	},
	"king": {
		"tunic": Color(0.20, 0.20, 0.30), "armor": Color(0.35, 0.33, 0.45),
		"skin": Color(0.55, 0.60, 0.62), "leather": Color(0.16, 0.15, 0.20),
		"cape": Color(0.14, 0.12, 0.24), "eyes": Color(0.55, 0.75, 1.0),
		"emissive": true, "alpha": 0.58,
	},
	"priest": {
		"tunic": Color(0.55, 0.55, 0.58), "armor": Color(0.60, 0.60, 0.62),
		"skin": Color(0.75, 0.72, 0.66), "leather": Color(0.30, 0.30, 0.32),
		"cape": Color(0.45, 0.45, 0.50), "eyes": Color(0.80, 0.90, 1.0),
		"emissive": true, "alpha": 0.55,
	},
}

const NOTES := {
	"caravan_note": {
		"title": "О клочке письма, спасённом от огня",
		"text": "«...караван идёт мимо Аш-Вейла, и я больше не сплю. Ночами с холмов дует так, будто кто-то дышит под ними. Старуха из Брода говорит: курган выдохнул. Если доберусь до Брода живым — продам оружие, куплю дом у моря и никогда больше не вернусь на север. Бьёрн.»",
	},
}

## Static helper used by runners.
static func quest(id: String) -> Dictionary:
	return QUESTS.get(id, {})


static func stages(id: String) -> Array:
	return quest(id).get("stages", [])
