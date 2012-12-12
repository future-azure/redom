class OthelloConnection
  include Redom::Connection

  TYPE_BLACK = 1
  TYPE_WHITE = -1
  DIRECTIONS = [
    [0, -1],
    [-1, -1],
    [-1, 0],
    [-1, 1],
    [0, 1],
    [1, 1],
    [1, 0],
    [1, -1]
  ]
  PIECES = {
    1 => "\u25cf",
    -1 => "\u25cb"
  }

  def on_open
    @opponent = nil
    @started = false
    @pieces = Hash.new
    @turn = 0

    table = '<table class="tbl">'
    0.upto(7).each { |y|
      table << '<tr>'
      0.upto(7).each { |x|
        table << "<td id=\"#{y}#{x}\"></td>"
      }
      table << '</tr>'
    }
    document.getElementById('board').innerHTML = table

    loop { |y, x|
      piece = document.getElementById(id = "#{y}#{x}")
      piece.onclick = :on_click
      @pieces[id] = piece
    }
    @msg = document.getElementById('msg')

    user_agent = navigator.userAgent.sync
    @src_element = true
    if user_agent =~ /firefox/i
      @src_element = false
    end

    document.getElementById('start').onclick = :start
  end
  attr_accessor :opponent, :started

  def on_close
    if @opponent
      @opponent.player_disconnected
      sync(@opponent){}
    end
  end

  def start(event)
    @started = true
    @turn = 0
    document.getElementById('start').disabled = true
    @msg.innerHTML = "Waiting for player..."
    @board = [[], [], [], [], [], [], [], []]
    loop { |y, x|
      @board[y][x] = 0
      @pieces["#{y}#{x}"].innerHTML = ""
    }
    @board[3][3] = @board[4][4] = TYPE_BLACK
    @board[3][4] = @board[4][3] = TYPE_WHITE
    @pieces['33'].innerHTML = PIECES[TYPE_BLACK]
    @pieces['44'].innerHTML = PIECES[TYPE_BLACK]
    @pieces['34'].innerHTML = PIECES[TYPE_WHITE]
    @pieces['43'].innerHTML = PIECES[TYPE_WHITE]

    connections.each { |conn|
      if conn != self && !conn.opponent && conn.started
        @opponent = conn
        conn.opponent = self
        game_start(TYPE_WHITE)
        conn.game_start(TYPE_BLACK)
        sync(conn){}
        break
      end
    }
  end

  def game_start(type)
    @turn = TYPE_BLACK
    @type = type
    @left = 60

    if @type == @turn
      @msg.innerHTML = "Your turn. #{PIECES[@type]}"
    else
      @msg.innerHTML = "Oppenent's turn. #{PIECES[-@type]}"
    end
  end

  def on_click(event)
    return unless @turn == @type

    if @src_element
      ele = event.srcElement
    else
      ele = event.target
    end

    id = ele.id.sync
    check_win(id[0].to_i, id[1].to_i)
  end

  def check_win(py, px)
    return unless @board[py][px] == 0
    valid = false
    DIRECTIONS.each { |dir|
      valid = check_direction(@type, py, px, dir, true) || valid
    }
    return unless valid

    @left -= 1
    loop { |y, x|
      if @board[y][x] == 0
        DIRECTIONS.each { |dir|
          if check_direction(-@type, y, x, dir, false)
            @turn = -@type
            @msg.innerHTML = "Opponent's turn. #{PIECES[-@type]}"
            @opponent.update_board(@board)
            sync(@opponent){}
            return
          end
        }
      end
    }

    if @left > 0
      @msg.innerHTML = 'You win!'
      @opponent.update_board(@board, [1, -1])
      sync(@opponent){}
    else
      count = 0
      loop { |y, x|
        count += 1 if @board[y][x] == @type
      }
      if count != 32
        @msg.innerHTML = "You #{count > 32 ? 'win' : 'lose'}! (#{count}#{PIECES[@type]} vs #{64 - count}#{PIECES[-@type]})"
      else
        @msg.innerHTML = "Draw game!"
      end
      @opponent.update_board(@board, [count, 64 - count])
      sync(@opponent){}
    end
    @turn = 0
    @opponent = nil
    @started = false
    document.getElementById('start').disabled = false
  end

  def check_direction(type, y, x, dir, update)
    count = 0
    oy = y; ox = x
    y += dir[0]; x += dir[1]
    while y >= 0 && y < 8 && x >= 0 && x < 8
      case @board[y][x]
      when -type
        count += 1
        y += dir[0]; x += dir[1]
      when type
        if count == 0
          break
        else
          if update
            @board[oy][ox] = type
            @pieces["#{oy}#{ox}"].innerHTML = PIECES[type]
            y -= dir[0]; x -= dir[1]
            while y != oy || x != ox
              @board[y][x] = type
              @pieces["#{y}#{x}"].innerHTML = PIECES[type]
              y -= dir[0]; x -= dir[1]
            end
          end
          return true
        end
      else
        break
      end
    end
    return false
  end

  def update_board(board, score = nil)
    @left -= 1
    loop { |y, x|
      if @board[y][x] != board[y][x]
        @board[y][x] = board[y][x]
        @pieces["#{y}#{x}"].innerHTML = PIECES[board[y][x]]
      end
    }

    if score
      if score[0] == score[1]
        @msg.innerHTML = "Draw game!"
      else
        result = "(#{score[1]}#{PIECES[@type]} vs #{score[0]}#{PIECES[-@type]})"
        @msg.innerHTML = "You #{score[0] < score[1] ? 'win' : 'lose'}! #{score[1] > 0 ? result : ''}"
      end
      @turn = 0
      @opponent = nil
      @started = false
      document.getElementById('start').disabled = false
    else
      @turn = @type
      @msg.innerHTML = "Your turn. #{PIECES[@type]}"
    end
  end

  def player_disconnected
    @msg.innerHTML = "Player disconnected!"
    @turn = 0
    @opponent = nil
    @started = false
    document.getElementById('start').disabled = false
  end

  def loop(&blk)
    0.upto(7).each { |y|
      0.upto(7).each { |x|
        yield(y, x)
      }
    }
  end
end
