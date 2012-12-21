class LifeGameConnection
  include Redom::Connection

  SIZE = 30
  LEN = 15

  def on_open
    src = %Q{
      board = "<table id='board' width='\#{#{SIZE} * #{LEN}}' height='\#{#{SIZE} * #{LEN}}'>"
      #{SIZE}.times { |i|
        board += "<tr>"
        #{SIZE}.times { |j|
          board += "<td id='\#{i}_\#{j}'></td>"
        }
        board += "</tr>"
      }
      board += "</table>"
      document.getElementById('main').innerHTML = board

      def mouse_over(event)
        cell = event.target
        pos = cell.id.split('_')
        if @@data[pos[0].to_i][pos[1].to_i] == -1
          cell.style.backgroundColor = 'grey'
        end
      end

      def mouse_out(event)
        cell = event.target
        pos = cell.id.split('_')
        if @@data[pos[0].to_i][pos[1].to_i] == -1
          cell.style.backgroundColor = 'white'
        end
      end

      def refresh
        pos = []
        #{SIZE}.times { |i|
          #{SIZE}.times { |j|
            if check(i, j)
              pos << [i, j]
            end
          }
        }
        pos.each { |p|
          if @@data[p[0]][p[1]] == 1
            @@data[p[0]][p[1]] = -1
            @@cells[p[0]][p[1]].style.backgroundColor = 'white'
          else
            @@data[p[0]][p[1]] = 1
            @@cells[p[0]][p[1]].style.backgroundColor = 'black'
          end
        }

        document.getElementById('counter').value = (@@counter += 1)
      end

      def check(i, j)
        count = 0
        count += 1 if i > 0 && j > 0 && @@data[i - 1][j - 1] == 1
        count += 1 if i > 0 && @@data[i - 1][j] == 1
        count += 1 if i > 0 && j < #{SIZE - 1} && @@data[i - 1][j + 1] == 1
        count += 1 if j < #{SIZE - 1} && @@data[i][j + 1] == 1
        count += 1 if i < #{SIZE - 1} && j < #{SIZE - 1} && @@data[i + 1][j + 1] == 1
        count += 1 if i < #{SIZE - 1} && @@data[i + 1][j] == 1
        count += 1 if i < #{SIZE - 1} && j > 0 && @@data[i + 1][j - 1] == 1
        count += 1 if j > 0 && @@data[i][j - 1] == 1
        (@@data[i][j] == -1 && count == 3) || (@@data[i][j] == 1 && (count <= 1 || count >= 4))
      end

      def create(i, j)
        @@data[i][j] = 1
        @@cells[i][j].style.backgroundColor = 'black'
      end

      #{SIZE}.times { |i|
        #{SIZE}.times { |j|
          cell = document.getElementById("\#{i}_\#{j}")
          cell.onmouseover = :mouse_over
          cell.onmouseout = :mouse_out
          cell.onclick = :on_click
        }
      }

      @@data = []
      @@cells = []
      @@counter = 0
      #{SIZE}.times { |i|
        @@data[i] = []
        @@cells[i] = []
        #{SIZE}.times { |j|
          @@data[i][j] = -1
          @@cells[i][j] = document.getElementById(i + '_' + j)
        }
      }
      create 13, 14
      create 14, 13
      create 14, 14
      create 14, 15
      create 15, 14

      setInterval :refresh, 1000
    }

    window.eval parse(src)
  end

  def on_click(event)
    pos = event.target.id.sync.split('_')
    connections.each { |conn|
      conn.async.click_cell pos[0].to_i, pos[1].to_i
    }
  end

  def click_cell(i, j)
    src = parse %Q{
      create(#{i - 1}, #{j}) if #{i} > 0
      create(#{i + 1}, #{j}) if #{i} < #{SIZE - 1}
      create(#{i}, #{j})
      create(#{i}, #{j - 1}) if #{j} > 0
      create(#{i}, #{j + 1}) if #{j} < #{SIZE - 1}
    }
    window.eval src
  end

  def on_error(error)
    puts '--------- ERROR ----------'
    puts error
  end
end
