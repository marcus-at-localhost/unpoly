###**
Params
======

class up.params
###
up.params = (($) ->
  u = up.util

  detectNature = (params) ->
    if u.isMissing(params)
      'missing'
    else if u.isArray(params)
      'array'
    else if u.isString(params)
      'query'
    else if u.isFormData(params)
      'formData'
    else if u.isObject(params)
      'object'
    else
      up.fail("Unsupport params type: %o", params)

  ###**
  Returns an array representation of the given `params`.

  Each array element will be an object with `{ name }` and `{ key }` properties.

  If `params` is a nested object, the nesting will be flattened and expressed
  in `{ name }` properties instead.

  @function up.params.toArray
  ###
  toArray = (params) ->
    switch detectNature(params)
      when 'missing'
        # No nesting conversion since we're just returning an empty list
        []
      when 'array'
       # No nesting conversion since we're not changing param type
        params
      when 'query'
        # No nesting conversion since we're converting from one unnested type to another
        buildArrayFromQuery(params)
      when 'formData'
        buildArrayFromFormData(params)
      when 'object'
        # We need to flatten the nesting from the given object
        buildArrayFromNestedObject(params)

  ###**
  Returns an object representation of the given `params`.

  The object will have a nested structure if `params` has keys like `foo[bar]` or `baz[]`.

  @function up.params.toArray
  ###
  toObject = (params) ->
    switch detectNature(params)
      when 'missing'
        # No nesting conversion since we're just returning an object
        {}
      when 'array', 'query', 'formData'
        # We must create a nested object from the given, flat array or FormData keys.
        # We don't want to duplicate the logic to parse a query string, so we're
        # converting to array first.
        buildNestedObjectFromArray(toArray(params))
      when 'object'
        # No nesting conversion since we're not changing param types.
        params

  ###**
  Returns [`FormData`](https://developer.mozilla.org/en-US/docs/Web/API/FormData) representation of the given `params`.

  If `params` is a nested object, the nesting will be flattened and expressed
  in the `FormData` keys using square bracket notation (e.g. `user[name]`).

  @function up.params.toArray
  ###
  toFormData = (params) ->
    switch detectNature(params)
      when 'missing'
        # Return an empty FormData object
        new FormData()
      when 'array', 'query', 'object'
        buildFormDataFromArray(toArray(params))
      when 'formData'
        params

  ###**
  Returns an query string for the given `params`.

  If `params` is a nested object, the nesting will be flattened and expressed
  with square bracket notiation in the query keys (e.g. `user[name]`).

  @function up.params.toString
  ###
  toQuery = (params, options = {}) ->
    query = switch detectNature(params)
      when 'missing'
        ''
      when 'query'
        params
      when 'array', 'formData', 'object'
        buildQueryFromArray(toArray(params))

    purpose = options.purpose || 'url'
    switch purpose
      when 'url'
        query = query.replace(/\+/g, '%20')
      when 'form'
        query = query.replace(/\%20/g, '+')
      else
        up.fail('Unknown purpose %o', purpose)

    query

  ###**
  # Adds the given name (which might have nesting marks like `foo[bar][][baz]`) and
  # string value to the given object. The name is recursively expanded to create
  # an object of nested sub-objects and arrays.
  #
  # Throws an error if the given name indicates a structure that is incompatible
  # with the existing structure in the given object.
  #
  # @function addToNestedObject
  # @internal
  # @param {Object} obj
  # @param {string} name
  # @param {string} value
  ###
  addToNestedObject = (obj, name, value) ->
    # Parse the name:
    # $1: the next names key without square brackets
    # $2: the rest of the key until the end
    match = /^[\[\]]*([^\[\]]+)\]*(.*?)$/.exec(name)

    k = match?[1]
    after = match?[2]

    console.log("!!! k is %o, v is %o, name is %o", k, value, name)

    if u.isBlank(k)
      if u.isGiven(value) && name == "[]"
        return [value]
      else
        return null

    if after == ''
      safeSet(obj, k, value)
    else if after == "["
      safeSet(obj, name, value)
    else if after == "[]"
      assertTypeForNestedKey(obj, k, 'Array', [])
      obj[k].push(value)
    else if match = (/^\[\]\[([^\[\]]+)\]$/.exec(after) || /^\[\](.+)$/.exec(after))
      childKey = match[1]
      assertTypeForNestedKey(obj, k, 'Array', [])
      lastObject = u.last(obj[k])
      # If the last element in the array is an object, we add more properties to that object,
      # but only if that same property hasn't been set on the object before.
      # If we have seen it before (or if the last elementis not an object) we assume the user
      # wants to push a new value into the array.
      if u.isObject(lastObject) && !nestedObjectHasDeepKey(lastObject, childKey)
        addToNestedObject(lastObject, childKey, value)
      else
        obj[k].push addToNestedObject({}, childKey, value)
    else
      assertTypeForNestedKey(obj, k, 'Object', {})
      safeSet(obj, k, addToNestedObject(obj[k], after, value))

    obj

  safeSet = (obj, k, value) ->
    unless Object.prototype.hasOwnProperty(k)
      obj[k] = value

  assertTypeForNestedKey = (obj, k, type, defaultValue) ->
    if value = obj[k]
      unless u["is#{type}"](value)
        up.fail("expected #{type} for params key %o, but got %o", k, value)
    else
      obj[k] = defaultValue

  nestedObjectHasDeepKey = (hash, key) ->
    console.info("nestedParamsObjectHasKey (%o, %o)", hash, key)
    return false if /\[\]/.test(key)

    keyParts = key.split(/[\[\]]+/)

    console.info("has keyParts %o", keyParts)

    for keyPart in keyParts
      console.info("nestedParamsObjectHasKey with keyPart %o and hash %o", keyPart, hash)
      continue if keyPart == ''
      return false unless u.isObject(hash) && hash.hasOwnProperty(keyPart)
      hash = hash[keyPart]

    console.info("nestedParamsObjectHasKey returns TRUE")

    true

  arrayEntryToQuery = (entry) ->
    value = entry.value
    return undefined unless canValueExistInQuery(value)
    query = encodeURIComponent(entry.name)
    # There is a subtle difference when encoding blank values:
    # 1. An undefined or null value is encoded to `key` with no equals sign
    # 2. An empty string value is encoded to `key=` with an equals sign but no value
    if u.isGiven(value)
      query += "="
      query += encodeURIComponent(value)
    query

  ###**
  Returns whether the given value can be encoded into a query string.

  We will have `File` values in our params when we serialize a form with a file input.
  These entries will be filtered out when converting to a query string.
  ###
  canValueExistInQuery = (value) ->
    u.isMissing(value) || u.isString(value) || u.isNumber(value) || u.isBoolean(value)

  buildQueryFromArray = (array) ->
    parts = u.map(array, arrayEntryToQuery)
    parts = u.compact(parts)
    parts.join('&')

  buildArrayFromQuery = (query) ->
    array = []
    for part in query.split('&')
      if u.isPresent(part)
        [name, value] = part.split('=')
        name = decodeURIComponent(name)
        # There are three forms we need to handle:
        # (1) foo=bar should become { name: 'foo', bar: 'bar' }
        # (2) foo=    should become { name: 'foo', bar: '' }
        # (3) foo     should become { name: 'foo', bar: null }
        if u.isGiven(value)
          value = decodeURIComponent(value)
        else
          value = null
        array.push({ name, value })
    array

  buildArrayFromNestedObject = (value, prefix) ->
    if u.isArray(value)
      u.flatMap value, (v) -> buildArrayFromNestedObject(v, "#{prefix}[]")
    else if u.isObject(value)
      entries = []
      for k, v of value
        p = if prefix then "#{prefix}[#{k}]" else k
        entries = entries.concat(buildArrayFromNestedObject(v, p))
      entries
    else if u.isMissing(value)
      [{ name: prefix, value: null }]
    else
      if u.isMissing(prefix)
        throw new Error("value must be a Hash")
      [ { name: prefix, value: value } ]

  buildNestedObjectFromArray = (array) ->
      obj = {}
      for entry in array
        addToNestedObject(obj, entry.name, entry.value)
      obj

  buildArrayFromFormData = (formData) ->
    ensureCanInspectFormData()
    array = []
    iterator = formData.entries()
    while entry = iterator.next() && !entry.done
      [name, value] = entry.value
      array.push({ name, value })
    array

  buildFormDataFromArray = (array) ->
    formData = new FormData()
    for entry in array
      formData.append(entry.name, entry.value)
    formData

  ensureCanInspectFormData = ->
    # Throw a nice error for IE11
    unless up.browser.canInspectFormData()
      up.fail('This browser cannot inspect FormData values. Consider storing params as objects or arrays.')

  buildURL = (base, params) ->
    parts = [base, toQuery(params)]
    parts = u.select(parts, u.isPresent)
    separator = if u.contains(base, '?') then '&' else '?'
    parts.join(separator)

  ###**
  Adds to the given `params` a new  entry with the given `name` and `value`.

  The given `params` is changed in-place, if possible.
  The return value is always a params value that includes the new entry.

  @function up.params.add
  @param {string|object|FormData|Array|undefined} params
  @param {string} name
  @param {any} value
  @return {string|object|FormData|Array}
  ###
  add = (params, name, value) ->
    newEntry = [{ name, value }]
    assign(params, newEntry)

  ###**
  Returns a new params value that contains entries from both `params` and `otherParams`.

  The given `params` argument is not changed.

  @function up.params.merge
  @param {string|object|FormData|Array|undefined} params
  @param {string|object|FormData|Array|undefined} otherParams
  @return {string|object|FormData|Array}
  ###
  merge = (params, otherParams) ->
    switch detectNature(params)
      when 'missing'
        merge({}, otherParams)
      when 'array'
        otherArray = toArray(otherParams)
        params.concat(otherArray)
      when 'formData'
        formData = new FormData()
        assign(formData, params)
        assign(formData, otherParams)
        formData
      when 'query'
        otherQuery = toQuery(otherParams)
        parts = u.select([params, otherQuery], u.isPresent)
        parts.join('&')
      when 'object'
        u.deepMerge(params, toObject(otherParams))

  ###**
  Extends the given `params` with entries from the given `otherParams`.

  The given `params` is changed in-place, if possible.
  The return value is always a params value that includes the new entries.

  @function up.params.assign
  @param {string|object|FormData|Array|undefined} params
  @param {string|object|FormData|Array|undefined} otherParams
  @return {string|object|FormData|Array}
  ###
  assign = (params, otherParams) ->
    switch detectNature(params)
      when 'array'
        otherArray = toArray(otherParams)
        params.push(otherArray...)
      when 'formData'
        otherArray = toArray(otherParams)
        for entry in otherArray
          params.append(entry.name, entry.value)
        params
      when 'object'
        u.deepAssign(params, toObject(otherParams))
      when 'query', 'missing'
        # `params` is immutable, so we merge instead.
        merge(params, otherParams)

  submittingButton = (form) ->
    $form = $(form)
    submitButtonSelector = 'input[type=submit], button[type=submit], button:not([type])'
    $activeElement = $(document.activeElement)
    if $activeElement.is(submitButtonSelector) && $form.has($activeElement)
      $activeElement[0]
    else
      # If no button is focused, we assume the first button in the form.
      $form.find(submitButtonSelector)[0]

  ###**
  Extracts request params from the given '<form>`.

  @function up.params.fromForm
  @param {Element|jQuery|string} form
  @return {Object}
  ###
  fromForm = (form ,options) ->
    form = u.element(form)
    options = u.options(options)
    params = {}

    inputs = u.toArray(form.querySelectorAll('select, input, textarea, .up-can-value'))
    if button = submittingButton(form)
      inputs.push(button)

    u.each inputs, (input) ->
      # Don't use the #name property, which is only available for native
      # input elements, but not Unpoly components.
      name = input.getAttribute('name')
      if input && name && !input.disabled
        # There are four cases:
        # 1. The input has an undefined value. We don't add it to the params.
        # 2. The input is [multiple] and clientValue() returns an array.
        #    We add them all to the params. Input's [name] should be an array ([] suffix)
        #    for this to be unpacked conveniently on the server.
        # 3. The input has another defined value. We add it to the params.
        valueOrValues = up.syntax.clientValue(input)
        u.each u.wrapArray(valueOrValues), (value) ->
          add(params, name, value)

    params

  ###**
  Returns the [query string](https://en.wikipedia.org/wiki/Query_string) from the given URL.

  The query string is returned without a leading question mark (`?`).

  Returns `undefined` if the given URL has no query component.

  @function up.params.fromURL
  @param {string} url
  @return {string|undefined}
  @experimental
  ###
  fromURL = (url) ->
    urlParts = u.parseUrl(url)
    if query = urlParts.search
      query = query.replace(/^\?/, '')
      query

  toArray: toArray
  toObject: toObject
  toQuery: toQuery
  toFormData: toFormData
  buildURL: buildURL
  add: add
  assign: assign
  merge: merge
  fromForm: fromForm
  fromURL: fromURL

)(jQuery)
