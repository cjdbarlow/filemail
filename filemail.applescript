-- Mail Filer - File recent messages & attachments hierarchically into DEVONthink
-- Based on "Mail Rule - File messages & attachments hierarchically"
-- Created by Christian Grunenberg on Tue Feb 27 2018.
-- Copyright (c) 2012-2020. All rights reserved.
--
-- Modified to run as a standalone scheduled script (not a Mail rule).
-- New code: config loading; run handler; processMailbox handler; writeLog handler;
--           and the path-stripping block inside fileMessage.
-- The fileMessage handler body is original DEVONthink code, copyright as above.



-- ========= CONFIGURATION DEFAULTS =========
-- These are overridden at runtime from filemail.config (see filemail.config.example).
property pDatabasePath : ""
property pNoSubjectString : "(no subject)"  -- DEVONthink default
property pIncludedAccounts : {}
property pExcludedMailboxes : {}
property pHours : 0


-- ========= SCRIPTY BITS =========
-- Entry point: called when the script is run directly (e.g. via launchd or osascript)
on run
	-- Load configuration from filemail.config next to the script
	tell me
		set scriptPath to POSIX path of (path to me)
		set configDir to do shell script "dirname " & quoted form of scriptPath
		set configFile to configDir & "/filemail.config"
	end tell

	try
		set pDatabasePath to do shell script "grep '^DATABASE_PATH=' " & quoted form of configFile & " | cut -d= -f2-"
		set pHours to (do shell script "grep '^HOURS=' " & quoted form of configFile & " | cut -d= -f2-") as integer
		set accountsStr to do shell script "grep '^INCLUDED_ACCOUNTS=' " & quoted form of configFile & " | cut -d= -f2-"
		set excludedStr to do shell script "grep '^EXCLUDED_MAILBOXES=' " & quoted form of configFile & " | cut -d= -f2-"
		set tid to AppleScript's text item delimiters
		set AppleScript's text item delimiters to ","
		set pIncludedAccounts to text items of accountsStr
		set pExcludedMailboxes to text items of excludedStr
		set AppleScript's text item delimiters to tid
	on error errMsg
		writeLog("ERROR: failed to load config from " & configFile & ": " & errMsg)
		error "Config load failed"
	end try

	writeLog("=== filemail started: pHours=" & pHours & ", accounts=" & (pIncludedAccounts as string) & " ===")

	tell application id "DNtp"
		if pDatabasePath is "" then
			set dest_db to inbox
			my writeLog("Using DEVONthink global inbox")
		else
			set dest_db to open database pDatabasePath
			my writeLog("Opened database: " & pDatabasePath)
		end if
	end tell

	set theFolder to POSIX path of (path to temporary items)
	set cutoffDate to (current date) - (pHours * hours)
	writeLog("Cutoff date: " & (cutoffDate as string))

	tell application "Mail"
		repeat with acctName in pIncludedAccounts
			my writeLog("Processing account: " & acctName)
			try
				set theAcct to first account whose name is acctName
				repeat with mbx in mailboxes of theAcct
					my processMailbox(mbx, cutoffDate, theFolder, dest_db)
				end repeat
			on error errMsg
				my writeLog("ERROR: could not process account '" & acctName & "': " & errMsg)
			end try
		end repeat
	end tell

	writeLog("=== filemail finished ===")
end run


-- Recursively process a mailbox: file recent messages, then descend into children
on processMailbox(mbx, cutoffDate, theFolder, dest_db)
	tell application "Mail"
		set mbxName to name of mbx
		if pExcludedMailboxes contains mbxName then
			my writeLog("Skipping excluded mailbox: " & mbxName)
			return
		end if

		set recentMessages to (messages of mbx whose date received >= cutoffDate)
		set msgCount to count of recentMessages
		my writeLog("Mailbox: " & mbxName & " — " & msgCount & " recent message(s)")

		repeat with msg in recentMessages
			my fileMessage(msg, theFolder, dest_db)
		end repeat

		repeat with child in mailboxes of mbx
			my processMailbox(child, cutoffDate, theFolder, dest_db)
		end repeat
	end tell
end processMailbox


-- File a single message into DEVONthink, mirroring its mailbox hierarchy.
-- Core logic is original DEVONthink code (copyright above).
-- Path-stripping block strips the /Apple Mail/AccountName prefix.
on fileMessage(theMessage, theFolder, dest_db)
	tell application "Mail"
		try
			tell theMessage
				set {theDateReceived, theDateSent, theSender, theSubject, theSource, theReadFlag} to {the date received, the date sent, the sender, subject, the source, the read status}

				-- Build folder path by walking up the mailbox hierarchy
				set theMessageLocation to "/"
				try
					set theMailbox to mailbox of theMessage
					repeat while theMailbox is not missing value
						set theName to name of theMailbox
						set theMessageLocation to "/" & (theName as string) & theMessageLocation
						set theMailbox to container of theMailbox
					end repeat
				end try
				set theMessageLocation to "/Apple Mail" & theMessageLocation
				-- Strip the first two components (/Apple Mail/AccountName) leaving just /FolderName/...
				set tid to AppleScript's text item delimiters
				set AppleScript's text item delimiters to "/"
				set pathParts to text items of theMessageLocation
				if (count of pathParts) > 3 then
					set AppleScript's text item delimiters to "/"
					set theMessageLocation to "/" & ((items 4 thru -1 of pathParts) as text)
				else
					set theMessageLocation to "/"
				end if
				set AppleScript's text item delimiters to tid
			end tell

			set numAttachments to count of mail attachments of theMessage
			if theSubject is equal to "" then set theSubject to pNoSubjectString

			my writeLog("Filing: '" & theSubject & "' -> " & theMessageLocation)

			-- Create DEVONthink record
			tell application id "DNtp"
				set message_group to create location theMessageLocation in dest_db
				set theRecord to create record with {name:theSubject & ".eml", type:unknown, creation date:theDateSent, modification date:theDateReceived, URL:theSender, source:(theSource as string), unread:false} in message_group
				perform smart rule trigger import event record theRecord
				if numAttachments > 0 then set attachment_group to create location theMessageLocation & "/Attachments" in dest_db
			end tell

			-- Import attachments
			repeat with theAttachment in mail attachments of theMessage
				try
					if downloaded of theAttachment then
						set theFile to theFolder & (name of theAttachment)
						tell theAttachment to save in theFile
						tell application id "DNtp"
							set theAttachmentRecord to import path theFile to attachment_group
							set unread of theAttachmentRecord to false
							set URL of theAttachmentRecord to theSender
							perform smart rule trigger import event record theAttachmentRecord
						end tell
					end if
				end try
			end repeat
		on error errMsg
			my writeLog("ERROR filing message: " & errMsg)
		end try
	end tell
end fileMessage


-- Append a timestamped line to filemail.log next to the script
on writeLog(msg)
	tell me
		set scriptPath to POSIX path of (path to me)
		set logDir to do shell script "dirname " & quoted form of scriptPath
		do shell script "echo " & quoted form of ((current date) as string & "  " & msg) & " >> " & quoted form of (logDir & "/filemail.log")
	end tell
end writeLog
