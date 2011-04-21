<cfcomponent name="Facebook Connect" hint="Handles interaction with the Facebook Connect service">
  
	<cffunction name="init" access="public" output="false" returntype="Object">
		<cfargument name="apikey" type="String" required="true" />
		<cfargument name="secret" type="String" required="true" />

		<cfset this.apikey = arguments.apikey />
		<cfset this.secret = arguments.secret />

		<cfset this.fb_params = {} />
		<cfset this.api_root = 'http://api.new.facebook.com/restserver.php' />
		<cfset this.apiversion = '1.0' />

		<cfset this.validate_fb_params() />

		<cfreturn this />
	</cffunction>
  
	<cffunction name="makeRequest" access="public" output="false" returntype="Object" hint="Makes a request to the facebook api">
		<cfargument name="method" type="string" required="yes" />
		<cfargument name="params" type="struct" required="no" default="#StructNew()#" />

		<cfset StructInsert(arguments.params, "api_key", this.apikey) />
		<cfset StructInsert(arguments.params, "v", this.apiversion) />
		<cfset StructInsert(arguments.params, "format", 'json') />
		<cfset StructInsert(arguments.params, "method", arguments.method) />

		<!--- generate signature based on params up until now --->
		<cfset StructInsert(arguments.params, "sig", generate_sig(arguments.params, this.secret)) />

		<cfhttp url="#this.api_root#" method="post" multipart="yes" redirect="no">
			<cfloop collection="#arguments.params#" item="key">
				<cfhttpparam name="#key#" value="#arguments.params[key]#" type="formfield" /> 
			</cfloop>
		</cfhttp>
		<cfset response = DeserializeJSON(cfhttp.filecontent) />

		<cfif IsStruct(response) && StructKeyExists(response, 'error_code')>
			<cfreturn response />
		<cfelse>
			<cfreturn response />
		</cfif>
	</cffunction>
  
	<cffunction name="isSessionValid" access="public" returntype="Boolean">
    	<cfif StructisEmpty(this.fb_params)>
			<cfreturn false />
		</cfif>

		<cfset var requestParams = StructNew() />
		<cfset requestParams.session_key = this.fb_params['session_key'] />

		<cfset var is_valid = this.makeRequest('users.getLoggedInUser', requestParams) />

		<cfif isStruct(is_valid) && StructKeyExists(is_valid, 'error_code')>
			<cfreturn false />
		<cfelseif isNumeric(is_valid)>
			<cfreturn true />
		<cfelse>
			<cfreturn false />
		</cfif>
	</cffunction>
  
	<cffunction name="connectLogout" access="public" returntype="Boolean">
		<cfif StructKeyExists(this.fb_params, 'session_key')>
			<cfset var requestParams = StructNew() />
			
			<cfset requestParams.session_key = this.fb_params['session_key'] />

			<cfset var expire = this.makeRequest('auth.expireSession', requestParams) />
		</cfif>

		<cfreturn true />
	</cffunction>
  
	<cffunction name="get_params" access="public" returntype="Struct">
		<cfreturn this.fb_params />
	</cffunction>
  
	<cffunction name="validate_fb_params" access="public" returntype="boolean">
		<cfset this.fb_params = this.get_valid_fb_params(params: form, timeout: 48*3600, namespace: 'fb_sig') />

		<!--- check for data in the form or url scope first --->
		<cfif !StructIsEmpty(this.fb_params)>
			<cfset fb_params = this.get_valid_fb_params(url, 48*3600, 'fb_sig') />
			<cfset fb_post_params = this.get_valid_fb_params(form, 48*3600, 'fb_post_sig') />
			<cfset this.fb_params = StructAppend(fb_params, fb_post_params) />
		</cfif>

		<!--- looks like some data came in via post or get --->
		<cfif not StructIsEmpty(this.fb_params)>
			<cfset user = null />
			<cfset profile_user = null />
			<cfset canvas_user = null />
			<cfset expires = null />

			<cfif StructKeyExists(this.fb_params, 'user')><cfset user = this.fb_params['user'] /></cfif>
			<cfif StructKeyExists(this.fb_params, 'profile_user')><cfset user = this.fb_params['profile_user'] /></cfif>
			<cfif StructKeyExists(this.fb_params, 'canvas_user')><cfset user = this.fb_params['canvas_user'] /></cfif>
			<cfif StructKeyExists(this.fb_params, 'expires')><cfset user = this.fb_params['expires'] /></cfif>

			<cfif StructKeyExists(this.fb_params, 'session_key')>
				<cfset session_key = this.fb_params['session_key'] />
			<cfelseif  StructKeyExists(this.fb_params, 'profile_session_key')>
				<cfset session_key = this.fb_params['profile_session_key'] />
			<cfelse>
				<cfset session_key = '' />
			</cfif>
			<cfreturn true />
		<cfelse>
			<cfset this.fb_params = this.get_valid_fb_params(params: cookie, namespace: this.apikey) />
			<cfreturn true />
		</cfif>

		<cfreturn false />
	</cffunction>
  
	<cffunction name="clear_fb_params" access="public" returntype="Struct">
		<cfargument name="params" type="Struct" required="true" />
		<cfargument name="namespace" type="String" required="false" default="fb_sig" />

		<cfset var prefix = namespace & '_' />
		<cfset var prefix_len = Len(prefix) />

		<cfloop collection="#arguments.params#" item="key">
			<cfif Left(key, prefix_len) eq prefix>
				<cfset StructDelete(arguments.params, key) />
			</cfif>
		</cfloop>

		<cfreturn arguments.params />

	</cffunction>
  
  
	<cffunction name="get_valid_fb_params" access="public" returntype="Struct">
	<cfargument name="params" type="Struct" required="true" />
	<cfargument name="timeout" type="Numeric" required="false" />
	<cfargument name="namespace" type="String" required="false" default="fb_sig" />
		<cfset var prefix = namespace & '_' />
		<cfset var prefix_len = Len(prefix) />
		<cfset var fb_params = {} />
		<cfset var signature = "" />

		<cfif StructIsEmpty(params)>
			<cfreturn {} />
		</cfif>

		<cfloop collection="#arguments.params#" item="key">
			<cfif Left(key, prefix_len) eq prefix>
				<cfset fb_params[Trim(Right(key, Len(key) - prefix_len))] = arguments.params[key] />
			</cfif>
		</cfloop>

		<cfset unix_time = DateDiff("s", CreateDate(1970,1,1), Now()) />

		<!---<cfif StructKeyExists(arguments, 'timeout') && !StructKeyExists(fb_params, 'time') || now() - fb_params['time'] gt arguments.timeout>
		<cfreturn {} />
		</cfif>--->

		<cfif StructKeyExists(arguments.params, arguments.namespace)>
			<cfset signature = arguments.params[arguments.namespace] />
		</cfif>

		<cfif !Len(signature) || !(this.verify_signature(fb_params, signature))>
			<cfreturn {} />
		</cfif>

		<cfreturn fb_params />

	</cffunction>
  
  
	<cffunction name="verify_signature" access="public" returntype="Boolean">
		<cfargument name="fb_params" type="Struct" required="true" />
		<cfargument name="expected_sig" type="String" required="true" />

		<cfif arguments.expected_sig eq this.generate_sig(fb_params, this.secret)>
			<cfreturn true />
		<cfelse>
			<cfreturn false />
		</cfif>
	</cffunction>
    
	<cffunction name="generate_sig" access="public" returntype="String">
		<cfargument name="fb_params" type="Struct" required="true" />
		<cfargument name="secret" type="String" required="true" />

		<cfset var str = "" />
		<cfset var sorted_keys = ListToArray(ListSort(StructKeyList(arguments.fb_params), 'textnocase')) />

		<cfloop collection="#sorted_keys#" item="idx">
			<cfset str &= sorted_keys[idx] & "=" & arguments.fb_params[sorted_keys[idx]] />
		</cfloop>

		<cfset str &= arguments.secret />

		<cfreturn lcase(hash(str, 'md5')) />
	</cffunction>
  
</cfcomponent>
