-- include libraries
	require "resources.functions.config";
	require "resources.functions.explode";
	require "resources.functions.split";
	require "resources.functions.count";

	local log       = require "resources.functions.log".fax_retry
	local Database  = require "resources.functions.database"
	local Settings  = require "resources.functions.lazy_settings"
	local Tasks     = require "app.fax.resources.scripts.queue.tasks"
	local send_mail = require "resources.functions.send_mail"

	local fax_task_uuid  = env:getHeader('fax_task_uuid')
	local task           = Tasks.select_task(fax_task_uuid)
	if not task then
		log.warningf("Can not find fax task: %q", tostring(fax_task_uuid))
		return 
	end

-- show all channel variables
	if debug["fax_serialize"] then
		log.noticef("info:\n%s", env:serialize())
	end

	local dbh = Database.new('system')

-- Channel/FusionPBX variables
	local uuid                           = env:getHeader("uuid")
	local fax_queue_task_session         = env:getHeader('fax_queue_task_session')
	local domain_uuid                    = env:getHeader("domain_uuid")                  or task.domain_uuid
	local domain_name                    = env:getHeader("domain_name")                  or task.domain_name
	local origination_caller_id_name     = env:getHeader("origination_caller_id_name")   or '000000000000000'
	local origination_caller_id_number   = env:getHeader("origination_caller_id_number") or '000000000000000'
	local accountcode                    = env:getHeader("accountcode")
	local duration                       = tonumber(env:getHeader("billmsec"))           or 0
	local sip_to_user                    = env:getHeader("sip_to_user")
	local bridge_hangup_cause            = env:getHeader("bridge_hangup_cause")
	local hangup_cause_q850              = tonumber(env:getHeader("hangup_cause_q850"))
	local answered                       = duration > 0

-- fax variables
	local fax_success                    = env:getHeader('fax_success')
	local has_t38                        = env:getHeader('has_t38')                        or 'false'
	local t38_broken_boolean             = env:getHeader('t38_broken_boolean')             or ''
	local fax_result_code                = tonumber(env:getHeader('fax_result_code'))      or 2
	local fax_result_text                = env:getHeader('fax_result_text')                or 'FS_NOT_SET'
	local fax_ecm_used                   = env:getHeader('fax_ecm_used')                   or ''
	local fax_local_station_id           = env:getHeader('fax_local_station_id')           or ''
	local fax_document_transferred_pages = env:getHeader('fax_document_transferred_pages') or nil
	local fax_document_total_pages       = env:getHeader('fax_document_total_pages')       or nil
	local fax_image_resolution           = env:getHeader('fax_image_resolution')           or ''
	local fax_image_size                 = env:getHeader('fax_image_size')                 or nil
	local fax_bad_rows                   = env:getHeader('fax_bad_rows')                   or nil
	local fax_transfer_rate              = env:getHeader('fax_transfer_rate')              or nil
	local fax_v17_disabled               = env:getHeader('fax_v17_disabled')               or ''
	local fax_ecm_requested              = env:getHeader('fax_ecm_requested')              or ''
	local fax_remote_station_id          = env:getHeader('fax_remote_station_id')          or ''

	local fax_options = ("fax_use_ecm=%s,fax_enable_t38=%s,fax_enable_t38_request=%s,fax_disable_v17=%s"):format(
		env:getHeader('fax_use_ecm')            or '',
		env:getHeader('fax_enable_t38')         or '',
		env:getHeader('fax_enable_t38_request') or '',
		env:getHeader('fax_disable_v17')        or ''
	)

-- Fax task params
	local fax_uri                        = env:getHeader("fax_uri")                        or task.uri
	local fax_file                       = env:getHeader("fax_file")                       or task.fax_file
	local wav_file                       = env:getHeader("wav_file")                       or task.wav_file
	local fax_uuid                       = task.fax_uuid

-- Email variables
	local number_dialed = fax_uri:match("/([^/]-)%s*$")

	log.noticef([[<<< CALL RESULT >>>
    uuid:                          = '%s'
    task_session_uuid:             = '%s'
    answered:                      = '%s'
    fax_file:                      = '%s'
    wav_file:                      = '%s'
    fax_uri:                       = '%s'
    sip_to_user:                   = '%s'
    accountcode:                   = '%s'
    origination_caller_id_name:    = '%s'
    origination_caller_id_number:  = '%s'
    mailto_address:                = '%s'
    hangup_cause_q850:             = '%s'
    fax_options                    = '%s'
]],
    tostring(uuid)                         ,
    tostring(fax_queue_task_session)       ,
    tostring(answered)                     ,
    tostring(fax_file)                     ,
    tostring(wav_file)                     ,
    tostring(fax_uri)                      ,
    tostring(sip_to_user)                  ,
    tostring(accountcode)                  ,
    tostring(origination_caller_id_name)   ,
    tostring(origination_caller_id_number) ,
    tostring(task.reply_address)           ,
    tostring(hangup_cause_q850)            ,
    fax_options
)

	if fax_success then
		log.noticef([[<<< FAX RESULT >>>
    fax_success                    = '%s'
    has_t38                        = '%s'
    t38_broken_boolean             = '%s'
    fax_result_code                = '%s'
    fax_result_text                = '%s'
    fax_ecm_used                   = '%s'
    fax_local_station_id           = '%s'
    fax_document_transferred_pages = '%s'
    fax_document_total_pages       = '%s'
    fax_image_resolution           = '%s'
    fax_image_size                 = '%s'
    fax_bad_rows                   = '%s'
    fax_transfer_rate              = '%s'
    fax_v17_disabled               = '%s'
    fax_ecm_requested              = '%s'
    fax_remote_station_id          = '%s'
    '%s'
]],
			fax_success                    ,
			has_t38                        ,
			t38_broken_boolean             ,
			fax_result_code                ,
			fax_result_text                ,
			fax_ecm_used                   ,
			fax_local_station_id           ,
			fax_document_transferred_pages ,
			fax_document_total_pages       ,
			fax_image_resolution           ,
			fax_image_size                 ,
			fax_bad_rows                   ,
			fax_transfer_rate              ,
			fax_v17_disabled               ,
			fax_ecm_requested              ,
			fax_remote_station_id          ,
			'---------------------------------'
		)
	end

--get the values from the fax file
	if not (fax_uuid and domain_name) then
		local array = split(fax_file, "[\\/]+")
		domain_name   = domain_name or   array[#array - 3]
		local fax_extension = fax_extension or array[#array - 2]

		if not fax_uuid then
			local sql = "SELECT fax_uuid FROM v_fax "
			sql = sql .. "WHERE domain_uuid = '" .. domain_uuid .. "' "
			sql = sql .. "AND fax_extension = '" .. fax_extension .. "' "
			fax_uuid = dbh:first_value(sql);
		end
	end

--get the domain_uuid using the domain name required for multi-tenant
	if domain_name and not domain_uuid then
		local sql = "SELECT domain_uuid FROM v_domains ";
		sql = sql .. "WHERE domain_name = '" .. domain_name .. "' "
		domain_uuid = dbh:first_value(sql)
	end

	assert(domain_name and domain_uuid)

--settings
	local settings = Settings.new(dbh, domain_name, domain_uuid)
	local keep_local   = settings:get('fax', 'keep_local','boolean')
	local storage_type = (keep_local == "false") and "" or settings:get('fax', 'storage_type', 'text')

--be sure accountcode is not empty
	if (accountcode == nil) then
		accountcode = domain_name
	end

	local function opt(v, default)
		if v then return "'" .. v .. "'" end
		return default or 'NULL'
	end

	local function now_sql()
		return (database["type"] == "sqlite") and "'"..os.date("%Y-%m-%d %X").."'" or "now()";
	end

--add to fax logs
	do
		local fields = {
			"fax_log_uuid";
			"domain_uuid";
			"fax_uuid";
			"fax_success";
			"fax_result_code";
			"fax_result_text";
			"fax_file";
			"fax_ecm_used";
			"fax_local_station_id";
			"fax_document_transferred_pages";
			"fax_document_total_pages";
			"fax_image_resolution";
			"fax_image_size";
			"fax_bad_rows";
			"fax_transfer_rate";
			"fax_retry_attempts";
			"fax_retry_limit";
			"fax_retry_sleep";
			"fax_uri";
			"fax_date";
			"fax_epoch";
		}

		local values = {
			"'"..uuid .. "'";
			"'"..domain_uuid .. "'";
			opt(fax_uuid);
			opt(fax_success);
			opt(fax_result_code);
			opt(fax_result_text);
			opt(fax_file);
			opt(fax_ecm_used);
			opt(fax_local_station_id);
			opt(fax_document_transferred_pages, "'0'");
			opt(fax_document_total_pages, "'0'");
			opt(fax_image_resolution);
			opt(fax_image_size);
			opt(fax_bad_rows);
			opt(fax_transfer_rate);
			opt(fax_retry_attempts);
			opt(fax_retry_limit);
			opt(fax_retry_sleep);
			opt(fax_uri);
			now_sql();
			"'"..os.time().."' ";
		}

		local sql = "insert into v_fax_logs(" .. table.concat(fields, ",") .. ")" ..
			"values(" .. table.concat(values, ",") .. ")"

		if (debug["sql"]) then
			log.noticef("SQL: %s", sql);
		end

		dbh:query(sql);
	end

--prepare the headers
	local mail_x_headers = {
		["X-FusionPBX-Domain-UUID"] = domain_uuid;
		["X-FusionPBX-Domain-Name"] = domain_name;
		["X-FusionPBX-Call-UUID"]   = uuid;
		["X-FusionPBX-Email-Type"]  = 'email2fax';
	}

-- add the fax files
	if fax_success == "1" then

		if storage_type == "base64" then
			--include the base64 function
				require "resources.functions.base64";

			--base64 encode the file
				local f = io.open(fax_file, "rb");
				if not f then
					log.waitng("Can not find file %s", fax_file)
					storage_type = nil
				else
					local file_content = f:read("*all");
					f:close()
					fax_base64 = base64.encode(file_content)
				end
		end

	-- build SQL
		local sql do
			sql = {
				"insert into v_fax_files(";
					"fax_file_uuid";                    ",";
					"fax_uuid";                         ",";
					"fax_mode";                         ",";
					"fax_destination";                  ",";
					"fax_file_type";                    ",";
					"fax_file_path";                    ",";
					"fax_caller_id_name";               ",";
					"fax_caller_id_number";             ",";
					"fax_date";                         ",";
					"fax_epoch";                        ",";
					"fax_base64";                       ",";
					"domain_uuid";                      " ";
				") values (";
					opt(uuid);                          ",";
					opt(fax_uuid);                      ",";
					"'tx'";                             ",";
					opt(sip_to_user);                   ",";
					"'tif'";                            ",";
					opt(fax_file);                      ",";
					opt(origination_caller_id_name);    ",";
					opt(origination_caller_id_number);  ",";
					now_sql();                          ",";
					"'" .. os.time() .. "'";            ",";
					opt(fax_base64);                    ",";
					opt(domain_uuid);                   " ";
				")"
			}

			sql = table.concat(sql, "\n");
			if (debug["sql"]) then
				log.noticef("SQL: %s", sql);
			end
		end

		if storage_type == "base64" then
			local db_type, db_cnn = split_first(database["system"], "://", true)
			local luasql = require ("luasql." .. db_type);
			local env = assert (luasql[db_type]());
			local dbh = env:connect(db_cnn);
			dbh:execute(sql)
			dbh:close()
			env:close()
		else
			result = dbh:query(sql)
		end
	end

	if fax_success == "1" then
		--Success
		log.infof("RETRY STATS SUCCESS: GATEWAY[%s]", fax_options);

		if keep_local == "false" then
			os.remove(fax_file);
		end

		Tasks.remove_task(task)

		if task.reply_address and #task.reply_address > 0 then
			send_mail(mail_x_headers, task.reply_address, {
				"Fax to: " .. number_dialed .. " SENT",
				table.concat{
					"We are happy to report the fax was sent successfully.",
					"It has been attached for your records.",
				}
			})
		end
	end

	if fax_success ~= "1" then
		if not answered then
			log.noticef("no answer: %d", hangup_cause_q850)
		else
			if not fax_success then
				log.noticef("Fax not detected: %s", fax_options)
			else
				log.noticef("fax fail %s", fax_options)
			end
		end

		-- if task use group call then retry.lua will be called multiple times
		-- here we check eathre that channel which execute `exec.lua`
		-- Note that if there no one execute `exec.lua` we do not need call this
		-- becase it should deal in `next.lua`
		if fax_queue_task_session == uuid then
			Tasks.wait_task(task, answered, hangup_cause_q850)
			if task.status ~= 0 then
				Tasks.remove_task(task)
				if task.reply_address and #task.reply_address > 0 then
					send_mail(mail_x_headers, task.reply_address, {
						"Fax to: " .. number_dialed .. " FAILED",
						table.concat{
							"We are sorry the fax failed to go through. ",
							"It has been attached. Please check the number "..number_dialed..", ",
							"and if it was correct you might consider emailing it instead.",
						}
					})
				end
			end
		end
	end
