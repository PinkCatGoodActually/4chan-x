Redirect =
  archives:
    `<%=
      JSON.stringify(readJSON('archives.json'), null, 2)
        .replace(/\n {2,}(?!{)/g, ' ')
        .replace(/\n/g, '\n    ')
        .replace(/`/g, '\\`')
    %>`

  init: ->
    @selectArchives()
    @update() if Conf['archiveAutoUpdate'] and Conf['lastarchivecheck'] < Date.now() - 2 * $.DAY

  selectArchives: ->
    o =
      thread: {}
      post:   {}
      file:   {}
      report: {}

    archives = {}
    for data in Conf['archives']
      for key in ['boards', 'files']
        data[key] = [] unless data[key] instanceof Array
      {uid, name, boards, files, software, withCredentials} = data
      archives[JSON.stringify(uid ? name)] = data
      for boardID in boards
        unless withCredentials
          o.thread[boardID] = data unless boardID of o.thread
          o.post[boardID]   = data unless boardID of o.post   or software isnt 'foolfuuka'
          o.file[boardID]   = data unless boardID of o.file   or boardID  not in files
        o.report[boardID]   = data if name is 'fgts'

    for boardID, record of Conf['selectedArchives']
      for type, id of record
        if id is null
          delete o[type][boardID]
        else if archive = archives[JSON.stringify id]
          boards = if type is 'file' then archive.files else archive.boards
          o[type][boardID] = archive if boardID in boards

    Redirect.data = o

  update: (cb) ->
    urls = []
    responses = []
    nloaded = 0
    for url in Conf['archiveLists'].split('\n') when url[0] isnt '#'
      url = url.trim()
      urls.push url if url

    load = (i) -> ->
      fail = (action, msg) -> new Notice 'warning', "Error #{action} archive data from #{urls[i]}\n#{msg}", 20
      return fail 'fetching', (if @status then "#{@status} #{@statusText}" else 'Connection Error') unless @status is 200
      try
        response = JSON.parse @response
      catch err
        return fail 'parsing', err.message
      response = [response] unless response instanceof Array
      responses[i] = response
      nloaded++
      if nloaded is urls.length
        Redirect.parse responses, cb

    if urls.length
      for url, i in urls
        if url[0] in ['[', '{']
          load(i).call
            status:   200
            response: url
        else
          $.ajax url,
            responseType: 'text'
            onloadend: load(i)
    else
      Redirect.parse [], cb
    return

  parse: (responses, cb) ->
    archives = []
    archiveUIDs = {}
    for response in responses
      for data in response
        uid = JSON.stringify(data.uid ? data.name)
        if uid of archiveUIDs
          $.extend archiveUIDs[uid], data
        else
          archiveUIDs[uid] = data
          archives.push data
    items = {archives, lastarchivecheck: Date.now()}
    $.set items
    $.extend Conf, items
    Redirect.selectArchives()
    cb?()

  to: (dest, data) ->
    archive = (if dest in ['search', 'board'] then Redirect.data.thread else Redirect.data[dest])[data.boardID]
    return '' unless archive
    Redirect[dest] archive, data

  protocol: (archive) ->
    protocol = location.protocol
    unless archive[protocol[0...-1]]
      protocol = if protocol is 'https:' then 'http:' else 'https:'
    "#{protocol}//"

  thread: (archive, {boardID, threadID, postID}) ->
    # Keep the post number only if the location.hash was sent f.e.
    path = if threadID
      "#{boardID}/thread/#{threadID}"
    else
      "#{boardID}/post/#{postID}"
    if archive.software is 'foolfuuka'
      path += '/'
    if threadID and postID
      path += if archive.software is 'foolfuuka'
        "##{postID}"
      else
        "#p#{postID}"
    "#{Redirect.protocol archive}#{archive.domain}/#{path}"

  post: (archive, {boardID, postID}) ->
    # For fuuka-based archives:
    # https://github.com/eksopl/fuuka/issues/27
    protocol = Redirect.protocol archive
    url = "#{protocol}#{archive.domain}/_/api/chan/post/?board=#{boardID}&num=#{postID}"
    return '' unless Redirect.securityCheck url

    url

  file: (archive, {boardID, filename}) ->
    "#{Redirect.protocol archive}#{archive.domain}/#{boardID}/full_image/#{filename}"

  board: (archive, {boardID}) ->
    "#{Redirect.protocol archive}#{archive.domain}/#{boardID}/"

  search: (archive, {boardID, type, value}) ->
    type = if type is 'name'
      'username'
    else if type is 'MD5'
      'image'
    else
      type
    if type is 'capcode'
      value = {'Developer': 'dev'}[value] or value.toLowerCase()
    else if type is 'image'
      value = value.replace /[+/=]/g, (c) -> {'+': '-', '/': '_', '=': ''}[c]
    value = encodeURIComponent value
    path  = if archive.software is 'foolfuuka'
      "#{boardID}/search/#{type}/#{value}/"
    else if type is 'image'
      "#{boardID}/image/#{value}"
    else
      "#{boardID}/?task=search2&search_#{type}=#{value}"
    "#{Redirect.protocol archive}#{archive.domain}/#{path}"

  report: (archive, {boardID, postID}) ->
    "https://so.fgts.jp/report/?board=#{boardID}&no=#{postID}"

  securityCheck: (url) ->
    /^https:\/\//.test(url) or
    location.protocol is 'http:' or
    Conf['Exempt Archives from Encryption']

  navigate: (dest, data, alternative) ->
    Redirect.init() unless Redirect.data
    url = Redirect.to dest, data
    if url and (
      Redirect.securityCheck(url) or
      confirm "Redirect to #{url}?\n\nYour connection will not be encrypted."
    )
      location.replace url
    else if alternative
      location.replace alternative

return Redirect
