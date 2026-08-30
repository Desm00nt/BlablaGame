class_name ItemDB
extends RefCounted

## Static item catalogue. The player's inventory stores ids; everything the
## UI shows (name, description, icon type, actions) is looked up here.

const ITEMS := {
	"steel_sword": {
		"name": "Стальной меч",
		"type": "weapon",
		"desc": "Перекаленная сталь северных кузниц. Легла в руку так, будто ждала тебя.",
		"stat": "Урон 34",
	},
	"oak_shield": {
		"name": "Дубовый щит",
		"type": "shield",
		"desc": "Доски из курганного дуба и стальной умбон. Держи ПКМ — и удар чужого клинка вязнет в дереве. Встречный тайминг выбивает врага из равновесия.",
		"stat": "Блок 75% · Парирование",
	},
	"health_potion": {
		"name": "Зелье лечения",
		"type": "consumable",
		"use": "heal",
		"desc": "Мутный отвар из корня бересклета. На вкус как болото, но раны затягивает на глазах.",
		"stat": "+45 здоровья",
	},
	"whetstone": {
		"name": "Точильный камень",
		"type": "consumable",
		"use": "sharpen",
		"desc": "Серый брусок с Бродовской мельницы. Три раза им воспользоваться можно — потом сталь снимет камень в стружку.",
		"stat": "+8 к урону меча",
	},
	"ashen_shard": {
		"name": "Осколок Пепельной Короны",
		"type": "quest",
		"desc": "Один из семи замков, удерживающих существо под курганами. Тёплый, как чужая ладонь. Внутри что-то дышит.",
		"stat": "Реликвия",
	},
	"caravan_note": {
		"name": "Записка караванщика",
		"type": "note",
		"note": "caravan_note",
		"desc": "Клочок письма, спасённый от огня. Почерк дрожит.",
		"stat": "Читаемое",
	},
}


static func get_item(id: String) -> Dictionary:
	return ITEMS.get(id, {})


static func display_name(id: String) -> String:
	return str(get_item(id).get("name", id))


static func has_note(id: String) -> bool:
	return get_item(id).has("note")
