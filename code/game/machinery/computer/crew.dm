/// How often the sensor data is updated
#define SENSORS_UPDATE_PERIOD	10 SECONDS //How often the sensor data updates.
/// The job sorting ID associated with otherwise unknown jobs
#define UNKNOWN_JOB_ID			81

/obj/machinery/computer/crew
	name = "crew monitoring console"
	desc = "Used to monitor active health sensors built into most of the crew's uniforms."
	icon_screen = "crew"
	icon_keyboard = "med_key"
	use_power = IDLE_POWER_USE
	idle_power_usage = 250
	active_power_usage = 500
	circuit = /obj/item/circuitboard/computer/crew
	light_color = LIGHT_COLOR_BLUE

/obj/machinery/computer/crew/syndie
	icon_keyboard = "syndie_key"

/obj/machinery/computer/crew/interact(mob/user)
	GLOB.crewmonitor.show(user,src)

GLOBAL_DATUM_INIT(crewmonitor, /datum/crewmonitor, new)

/datum/crewmonitor
	/// List of user -> UI source
	var/list/ui_sources = list()
	/// Cache of data generated by z-level, used for serving the data within SENSOR_UPDATE_PERIOD of the last update
	var/list/data_by_z = list()
	/// Cache of last update time for each z-level
	var/list/last_update = list()
	/// Map of job to ID for sorting purposes
	var/list/jobs = list(
		// Note that jobs divisible by 10 are considered heads of staff, and bolded
		// 00: Manager
		"Manager" = 00,
		"Extraction Officer" = 01,
		"Records Officer" = 01,
		// 10-19: Security
		"Agent Captain" = 10,
		"Veteran Agent" = 11,
		"Senior Agent" = 12,
		"Agent" = 13,
		// 20-29: Medbay
		"Chief Medical Officer" = 20,
		"Chemist" = 21,
		"Virologist" = 22,
		"Medical Doctor" = 23,
		"Paramedic" = 24,
		// 30-39: Science
		"Research Director" = 30,
		"Scientist" = 31,
		"Roboticist" = 32,
		"Geneticist" = 33,
		// 40-49: Engineering
		"Chief Engineer" = 40,
		"Station Engineer" = 41,
		"Atmospheric Technician" = 42,
		"Void Technician" = 43,
		// 50-59: Cargo
		"Head of Personnel" = 50,
		"Quartermaster" = 51,
		"Shaft Miner" = 52,
		"Cargo Technician" = 53,
		// 60+: Civilian/other
		"Clerk" = 61,
		"Cook" = 62,
		"Botanist" = 63,
		"Curator" = 64,
		"Chaplain" = 65,
		"Clown" = 66,
		"Mime" = 67,
		"Janitor" = 68,
		"Lawyer" = 69,
		"Psychologist" = 71,
		// ANYTHING ELSE = UNKNOWN_JOB_ID, Unknowns/custom jobs will appear after civilians, and before assistants
		"Assistant" = 999,

		// Misc Lobotomy Corp roles; 150 - 159
		"Arbiter" = 150,

		// Tegustation Syndicate roles; 160 - 199
		"Syndicate Overlord" = 160,
		"Syndicate Mastermind" = 161,
		"Syndicate Commander" = 162,
		"Syndicate Admiral" = 170,
		"Syndicate Official" = 171,
		"Syndicate Captain" = 180,
		"Syndicate Assault Operative" = 181,
		"Syndicate Medical Doctor" = 182,
		"Syndicate Engineer" = 183,
		"Syndicate Ship Captain" = 190,
		"Syndicate Operative" = 191,
		"Syndicate" = 192,

		// 200-229: Centcom
		"Admiral" = 200,
		"CentCom Commander" = 210,
		"Custodian" = 211,
		"Medical Officer" = 212,
		"Research Officer" = 213,
		"Emergency Response Team Commander" = 220,
		"Security Response Officer" = 221,
		"Engineer Response Officer" = 222,
		"Medical Response Officer" = 223
	)

/datum/crewmonitor/ui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if (!ui)
		ui = new(user, src, "CrewConsole")
		ui.open()

/datum/crewmonitor/proc/show(mob/M, source)
	ui_sources[M] = source
	ui_interact(M)

/datum/crewmonitor/ui_host(mob/user)
	return ui_sources[user]

/datum/crewmonitor/ui_data(mob/user)
	var/z = user.z
	if(!z)
		var/turf/T = get_turf(user)
		z = T.z
	. = list(
		"sensors" = update_data(z),
		"link_allowed" = isAI(user)
	)

/datum/crewmonitor/proc/update_data(z)
	if(data_by_z["[z]"] && last_update["[z]"] && world.time <= last_update["[z]"] + SENSORS_UPDATE_PERIOD)
		return data_by_z["[z]"]

	var/list/results = list()
	for(var/tracked_mob in GLOB.suit_sensors_list | GLOB.nanite_sensors_list)
		if(!tracked_mob)
			stack_trace("Null entry in suit sensors or nanite sensors list.")
			continue

		var/mob/living/tracked_living_mob = tracked_mob

		// Check if z-level is correct
		var/turf/pos = get_turf(tracked_living_mob)

		// Is our target in nullspace for some reason?
		if(!pos)
			stack_trace("Tracked mob has no loc and is likely in nullspace: [tracked_living_mob] ([tracked_living_mob.type])")
			continue

		// Machinery and the target should be on the same level or different levels of the same station
		if(pos.z != z && (!is_station_level(pos.z) || !is_station_level(z)))
			continue

		var/sensor_mode

		// Set sensor level based on whether we're in the nanites list or the suit sensor list.
		if(tracked_living_mob in GLOB.nanite_sensors_list)
			sensor_mode = SENSOR_COORDS
		else
			var/mob/living/carbon/human/tracked_human = tracked_living_mob

			// Check their humanity.
			if(!ishuman(tracked_human))
				stack_trace("Non-human mob is in suit_sensors_list: [tracked_living_mob] ([tracked_living_mob.type])")
				continue

			// Check they have a uniform
			var/obj/item/clothing/under/uniform = tracked_human.w_uniform
			if (!istype(uniform))
				stack_trace("Human without a suit sensors compatible uniform is in suit_sensors_list: [tracked_human] ([tracked_human.type]) ([uniform?.type])")
				continue

			// Check if their uniform is in a compatible mode.
			if((uniform.has_sensor <= NO_SENSORS) || !uniform.sensor_mode)
				stack_trace("Human without active suit sensors is in suit_sensors_list: [tracked_human] ([tracked_human.type]) ([uniform.type])")
				continue

			sensor_mode = uniform.sensor_mode

		// The entry for this human
		var/list/entry = list(
			"ref" = REF(tracked_living_mob),
			"name" = "Unknown",
			"ijob" = UNKNOWN_JOB_ID
		)

		// ID and id-related data
		var/obj/item/card/id/id_card = tracked_living_mob.get_idcard(hand_first = FALSE)
		if (id_card)
			entry["name"] = id_card.registered_name
			entry["assignment"] = id_card.assignment
			entry["ijob"] = jobs[id_card.GetJobName()] // Tegu edit - Alt job titles

		// Binary living/dead status
		if (sensor_mode >= SENSOR_LIVING)
			entry["life_status"] = !tracked_living_mob.stat

		// Damage
		if (sensor_mode >= SENSOR_VITALS)
			entry += list(
				"oxydam" = round(tracked_living_mob.getOxyLoss(), 1),
				"toxdam" = round(tracked_living_mob.getToxLoss(), 1),
				"burndam" = round(tracked_living_mob.getFireLoss(), 1),
				"brutedam" = round(tracked_living_mob.getBruteLoss(), 1),
				"sandam" = round(tracked_living_mob.getSanityLoss(), 1)
			)

		// Location
		if (sensor_mode >= SENSOR_COORDS)
			entry["area"] = get_area_name(tracked_living_mob, format_text = TRUE)

		// Trackability
		entry["can_track"] = tracked_living_mob.can_track()

		results[++results.len] = entry

	// Cache result
	data_by_z["[z]"] = results
	last_update["[z]"] = world.time

	return results

/datum/crewmonitor/ui_act(action,params)
	. = ..()
	if(.)
		return
	switch (action)
		if ("select_person")
			var/mob/living/silicon/ai/AI = usr
			if(!istype(AI))
				return
			AI.ai_camera_track(params["name"])

#undef SENSORS_UPDATE_PERIOD
#undef UNKNOWN_JOB_ID
