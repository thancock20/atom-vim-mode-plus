{Point, Range} = require 'atom'
_    = require 'underscore-plus'
Base = require './base'

class TextObject extends Base
  @extend()
  complete: true
  recodable: false

  rangeToBeginningOfFile: (point) ->
    new Range(Point.ZERO, point)

  rangeToEndOfFile: (point) ->
    new Range(point, Point.INFINITY)

class CurrentSelection extends TextObject
  @extend()
  select: ->
    _.times @getCount(1), ->
      true

# Word
# -------------------------
class SelectWord extends TextObject
  select: ->
    for selection in @editor.getSelections()
      wordRegex = @wordRegExp ? selection.cursor.wordRegExp()
      @selectExclusive(selection, wordRegex)
      @selectInclusive(selection) if @inclusive
      not selection.isEmpty()

  selectExclusive: (selection, wordRegex) ->
    range = selection.cursor.getCurrentWordBufferRange({wordRegex})
    selection.setBufferRange(range)

  selectInclusive: (selection) ->
    scanRange = selection.cursor.getCurrentLineBufferRange()
    headPoint = selection.getHeadBufferPosition()
    scanRange.start = headPoint
    @editor.scanInBufferRange /\s+/, scanRange, ({range, stop}) ->
      if headPoint.isEqual(range.start)
        selection.selectToBufferPosition range.end
        stop()

class SelectInsideWord extends SelectWord
  @extend()

class SelectAWord extends SelectInsideWord
  @extend()
  inclusive: true

class SelectInsideWholeWord extends SelectWord
  @extend()
  wordRegExp: /\S+/

class SelectAWholeWord extends SelectInsideWholeWord
  @extend()
  inclusive: true

# Quote
# -------------------------
class SelectInsideQuotes extends TextObject
  char: null
  includeQuotes: false

  findForward: (fromPoint) ->
    pattern   = ///[^\\]?#{@char}///
    scanRange = @rangeToEndOfFile(fromPoint)
    point = null
    @editor.scanInBufferRange pattern, scanRange, ({range, stop}) ->
      point = range.end
      stop()
    point

  findBackward: (fromPoint) ->
    pattern   = ///[^\\]?#{@char}///
    scanRange = @rangeToBeginningOfFile(fromPoint)
    point = null
    @editor.backwardsScanInBufferRange pattern, scanRange, ({range, stop}) ->
      point = range.end
      stop()
    point

  select: ->
    for selection in @editor.getSelections()
      point  = selection.getHeadBufferPosition()
      start  = @findBackward(point)
      start ?= @findForward(point)
      end    = @findForward(start)?.traverse([0, -1])

      if start? and end?
        if @includeQuotes
          start = start.traverse([0, -1])
          end   = end.traverse([0, +1])
        selection.setBufferRange([start, end])
      not selection.isEmpty()

class SelectInsideDoubleQuotes extends SelectInsideQuotes
  char: '"'
class SelectAroundDoubleQuotes extends SelectInsideDoubleQuotes
  includeQuotes: true

class SelectInsideSingleQuotes extends SelectInsideQuotes
  char: '\''
class SelectAroundSingleQuotes extends SelectInsideSingleQuotes
  includeQuotes: true

class SelectInsideBackTicks extends SelectInsideQuotes
  @extend()
  char: '`'
class SelectAroundBackTicks extends SelectInsideBackTicks
  @extend()
  includeQuotes: true


# SelectInsideBrackets and the previous class defined (SelectInsideQuotes) are
# almost-but-not-quite-repeated code. They are different because of the depth
# checks in the bracket matcher.

class SelectInsideBrackets extends TextObject
  @extend()
  beginChar: null
  endChar: null
  includeBrackets: false
  # constructor: (@vimState, @beginChar, @endChar, @includeBrackets) ->
  #   super(@vimState)

  findOpeningBracket: (pos) ->
    pos = pos.copy()
    depth = 0
    while pos.row >= 0
      line = @editor.lineTextForBufferRow(pos.row)
      pos.column = line.length - 1 if pos.column is -1
      while pos.column >= 0
        switch line[pos.column]
          when @endChar then ++ depth
          when @beginChar
            return pos if -- depth < 0
        -- pos.column
      pos.column = -1
      -- pos.row

  findClosingBracket: (start) ->
    end = start.copy()
    depth = 0
    while end.row < @editor.getLineCount()
      endLine = @editor.lineTextForBufferRow(end.row)
      while end.column < endLine.length
        switch endLine[end.column]
          when @beginChar then ++ depth
          when @endChar
            if -- depth < 0
              -- start.column if @includeBrackets
              ++ end.column if @includeBrackets
              return end
        ++ end.column
      end.column = 0
      ++ end.row
    return

  select: ->
    for selection in @editor.getSelections()
      start = @findOpeningBracket(selection.cursor.getBufferPosition())
      if start?
        ++ start.column # skip the opening quote
        end = @findClosingBracket(start)
        if end?
          selection.setBufferRange([start, end])
      not selection.isEmpty()

class SelectInsideCurlyBrackets extends SelectInsideBrackets
  @extend()
  beginChar: '{'
  endChar: '}'
class SelectAroundCurlyBrackets extends SelectInsideCurlyBrackets
  @extend()
  includeBrackets: true

class SelectInsideAngleBrackets extends SelectInsideBrackets
  @extend()
  beginChar: '<'
  endChar: '>'
class SelectAroundAngleBrackets extends SelectInsideAngleBrackets
  @extend()
  includeBrackets: true

class SelectInsideTags extends SelectInsideBrackets
  @extend()
  beginChar: '>'
  endChar: '<'
class SelectAroundTags extends SelectInsideTags
  @extend()
  includeBrackets: true

class SelectInsideSquareBrackets extends SelectInsideBrackets
  @extend()
  beginChar: '['
  endChar: ']'
class SelectAroundSquareBrackets extends SelectInsideSquareBrackets
  @extend()
  includeBrackets: true

class SelectInsideParentheses extends SelectInsideBrackets
  @extend()
  beginChar: '('
  endChar: ')'
class SelectAroundParentheses extends SelectInsideParentheses
  @extend()
  includeBrackets: true

# Paragraph
# -------------------------
# In vim world Paragraph is defined as consecutive non-blank-line or consecutive blank-line.
# depending on the start line is blankline or not.
# Should change linewise selection.
# selectExclusive = (selection, wordRegex) ->
# In vim world Paragraph is defined as consecutive non-blank-line or consecutive blank-line.
# depending on the start line is blankline or not.
# Should change linewise selection.
class SelectInsideParagraph extends TextObject
  @extend()

  isWhiteSpaceRow: (row) ->
    /^\s*$/.test @editor.lineTextForBufferRow(row)

  getRange: (point) ->
    pattern = if @isWhiteSpaceRow(point.row) then /^.*\S.*$/ else /^\s*?$/
    start = @findStart(point, pattern)
    end = @findEnd(point, pattern)
    new Range(start, end)

  getNextRange: (point, direction) ->
    rowTraverse = switch direction
      when 'forward'  then +1
      when 'backward' then -1
    @getRange point.traverse([rowTraverse, 0])

  findStart: (fromPoint, pattern) ->
    scanRange = @rangeToBeginningOfFile(fromPoint)
    point = null
    @editor.backwardsScanInBufferRange pattern, scanRange, ({range, stop}) ->
      point = range.start.traverse([+1, 0])
      stop()
    point

  findEnd: (fromPoint, pattern) ->
    scanRange = @rangeToEndOfFile(fromPoint)
    point = null
    @editor.scanInBufferRange pattern, scanRange, ({range, stop}) =>
      point = range.start
      stop()
    point

  selectParagraph: (selection) ->
    [startRow, endRow] = selection.getBufferRowRange()
    selectionEndRow = selection.getBufferRange().end.row
    if startRow is endRow
      range = @getRange(new Point(startRow, 0))
      selection.setBufferRange(range)
    else # have direction
      if selection.isReversed()
        range = @getNextRange(new Point(startRow, 0), "backward")
        selection.selectToBufferPosition(range.start)
      else
        range = @getNextRange(new Point(endRow, 0), "forward")
        selection.selectToBufferPosition(range.end)

  select: ->
    for selection in @editor.getSelections()
      _.times @getCount(1), =>
        @selectParagraph(selection)
        @selectParagraph(selection) if @inclusive
      not selection.isEmpty()

class SelectAroundParagraph extends SelectInsideParagraph
  inclusive: true

module.exports = {
  TextObject,
  CurrentSelection,

  SelectInsideDoubleQuotes
  SelectAroundDoubleQuotes

  SelectInsideSingleQuotes
  SelectAroundSingleQuotes

  SelectInsideBackTicks
  SelectAroundBackTicks

  SelectInsideCurlyBrackets
  SelectAroundCurlyBrackets

  SelectInsideAngleBrackets
  SelectAroundAngleBrackets

  SelectInsideTags
  SelectAroundTags

  SelectInsideSquareBrackets
  SelectAroundSquareBrackets

  SelectInsideParentheses
  SelectAroundParentheses

  SelectInsideWord, SelectAWord,
  SelectInsideWholeWord, SelectAWholeWord,
  SelectInsideQuotes, SelectInsideBrackets,
  SelectInsideParagraph, SelectAroundParagraph
}
