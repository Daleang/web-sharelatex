Settings = require 'settings-sharelatex'
Path = require 'path'
FileWriter = require '../../infrastructure/FileWriter'
FileSystemImportManager = require '../Uploads/FileSystemImportManager'
ProjectEntityHandler = require '../Project/ProjectEntityHandler'
ProjectLocator = require '../Project/ProjectLocator'
EditorController = require '../Editor/EditorController'
Errors = require '../Errors/Errors'
moment = require 'moment'

module.exports = RestoreManager =
	restoreDocFromDeletedDoc: (user_id, project_id, doc_id, name, callback = (error, doc, folder_id) ->) ->
		# This is the legacy method for restoring a doc from the SL track-changes/deletedDocs system.
		# It looks up the deleted doc's contents, and then creates a new doc with the same content.
		# We don't actually remove the deleted doc entry, just create a new one from its lines.
		ProjectEntityHandler.getDoc project_id, doc_id, include_deleted: true, (error, lines) ->
			return callback(error) if error?
			addDocWithName = (name, callback) ->
				EditorController.addDoc project_id, null, name, lines, 'restore', user_id, callback
			RestoreManager._addEntityWithUniqueName addDocWithName, name, callback

	restoreFileFromV2: (user_id, project_id, version, pathname, callback = (error, entity) ->) ->
		RestoreManager._writeFileVersionToDisk project_id, version, pathname, (error, fsPath) ->
			return callback(error) if error?
			basename = Path.basename(pathname)
			dirname = Path.dirname(pathname)
			if dirname == '.' # no directory
				dirname = ''
			RestoreManager._findOrCreateFolder project_id, dirname, (error, parent_folder_id) ->
				return callback(error) if error?
				addEntityWithName = (name, callback) ->
					FileSystemImportManager.addEntity user_id, project_id, parent_folder_id, name, fsPath, false, callback
				RestoreManager._addEntityWithUniqueName addEntityWithName, basename, callback

	_findOrCreateFolder: (project_id, dirname, callback = (error, folder_id) ->) ->
		EditorController.mkdirp project_id, dirname, (error, newFolders, lastFolder) ->
			return callback(error) if error?
			return callback(null, lastFolder?._id)

	_addEntityWithUniqueName: (addEntityWithName, basename, callback = (error) ->) ->
		addEntityWithName basename, (error, entity) ->
			if error?
				if error instanceof Errors.InvalidNameError
					# likely a duplicate name, so try with a prefix
					date = moment(new Date()).format('Do MMM YY H:mm:ss')
					# Move extension to the end so the file type is preserved
					extension = Path.extname(basename)
					basename = Path.basename(basename, extension)
					basename = "#{basename} (Restored on #{date})"
					if extension != ''
						basename = "#{basename}#{extension}"
					addEntityWithName basename, callback
				else
					callback(error)
			else
				callback(null, entity)

	_writeFileVersionToDisk: (project_id, version, pathname, callback = (error, fsPath) ->) ->
		url = "#{Settings.apis.project_history.url}/project/#{project_id}/version/#{version}/#{encodeURIComponent(pathname)}"
		FileWriter.writeUrlToDisk project_id, url, callback