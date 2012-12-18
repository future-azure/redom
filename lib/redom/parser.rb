require 'opal'

module Redom
  class Parser < Opal::Parser
    # s(:lit, 1)
    # s(:lit, :foo)
    def process_lit(sexp, level)
      val = sexp.shift
      case val
      when Numeric
        level == :recv ? "(#{val.inspect})" : val.inspect
      when Symbol
        val.to_s.inspect + "_____"
      when Regexp
        val == // ? /^/.inspect : val.inspect
      when Range
        @helpers[:range] = true
        "__range(#{val.begin}, #{val.end}, #{val.exclude_end?})"
      else
        raise "Bad lit: #{val.inspect}"
      end
    end

    # Converts a ruby method name into its javascript equivalent for
    # a method/function call. All ruby method names get prefixed with
    # a '$', and if the name is a valid javascript identifier, it will
    # have a '.' prefix (for dot-calling), otherwise it will be
    # wrapped in brackets to use reference notation calling.
    #
    #     mid_to_jsid('foo')      # => ".$foo"
    #     mid_to_jsid('class')    # => ".$class"
    #     mid_to_jsid('==')       # => "['$==']"
    #     mid_to_jsid('name=')    # => "['$name=']"
    #
    # @param [String] mid ruby method id
    # @return [String]
    def mid_to_jsid(mid, djs_call = true)
      if /^([a-zA-Z0-9$_]+)=$/ =~ mid.to_s
        ".$djsAssign('#{$1}')"
      elsif '[]' == mid.to_s
        ".$djsCall('')"
      elsif /\=|\+|\-|\*|\/|\!|\?|\<|\>|\&|\||\^|\%|\~|\[/ =~ mid.to_s
        "['$#{mid}']"
      else
# djs
        # '.$' + mid
        if djs_call
          ".$djsCall('$#{mid}')"
        else
          ".$#{mid}"
        end
      end
    end

    def js_def(recvr, mid, args, stmts, line, end_line)
# djs
      jsid = mid_to_jsid(mid.to_s, false)

      if recvr
        @scope.defines_defs = true
        smethod = true if @scope.class_scope? && recvr.first == :self
        recv = process(recvr, :expr)
      else
        @scope.defines_defn = true
        recv = current_self
      end

      code = ''
      params = nil
      scope_name = nil
      uses_super = nil

      # opt args if last arg is sexp
      opt = args.pop if Array === args.last

      # block name &block
      if args.last.to_s.start_with? '&'
        block_name = args.pop.to_s[1..-1].to_sym
      end

      # splat args *splat
      if args.last.to_s.start_with? '*'
        if args.last == :*
          args.pop
        else
          splat = args[-1].to_s[1..-1].to_sym
          args[-1] = splat
          len = args.length - 2
        end
      end

      indent do
        in_scope(:def) do
          @scope.mid  = mid
          @scope.defs = true if recvr

          if block_name
            @scope.uses_block!
          end

          yielder = block_name || '__yield'
          @scope.block_name = yielder

          params = process args, :expr

          opt[1..-1].each do |o|
            next if o[2][2] == :undefined
            id = process s(:lvar, o[1]), :expr
            code += ("if (%s == null) {\n%s%s\n%s}" %
                      [id, @indent + INDENT, process(o, :expre), @indent])
          end if opt

          code += "#{splat} = __slice.call(arguments, #{len});" if splat
          code += "\n#@indent" + process(stmts, :stmt)

          # Returns the identity name if identified, nil otherwise
          scope_name = @scope.identity

          if @scope.uses_block?
            @scope.add_temp '__context'
            @scope.add_temp yielder

            blk = "\n%s%s = %s._p || nil, __context = %s._s, %s._p = null;\n%s" %
              [@indent, yielder, scope_name, yielder, scope_name, @indent]

            code = blk + code
          end

          uses_super = @scope.uses_super

          code = "#@indent#{@scope.to_vars}" + code
        end
      end

      defcode = "#{"#{scope_name} = " if scope_name}function(#{params}) {\n#{code}\n#@indent}"

      if recvr
        if smethod
          @scope.smethods << "$#{mid}"
          "#{ @scope.name }#{jsid} = #{defcode}"
        else
          "#{ recv }#{ jsid } = #{ defcode }"
        end
      elsif @scope.class_scope?
        @scope.methods << "$#{mid}"
        if uses_super
          @scope.add_temp uses_super
          uses_super = "#{uses_super} = #{@scope.proto}#{jsid};\n#@indent"
        end
        "#{uses_super}#{ @scope.proto }#{jsid} = #{defcode}"
      elsif @scope.type == :iter
        "def#{jsid} = #{defcode}"
      elsif @scope.type == :top
        "#{ current_self }#{ jsid } = #{ defcode }"
      else
        "def#{jsid} = #{defcode}"
      end
    end

    # s(:const, :const)
    def process_const(sexp, level)
      # "__scope.#{sexp.shift}"
      "__scope.$djsCall('#{sexp.shift}')()"
    end

    # s(:call, recv, :mid, s(:arglist))
    # s(:call, nil, :mid, s(:arglist))
    def process_call(sexp, level)
      recv, meth, arglist, iter = sexp
      mid = mid_to_jsid meth.to_s

      case meth
      when :attr_reader, :attr_writer, :attr_accessor
        return handle_attr_optimize(meth, arglist[1..-1])
      when :block_given?
        return js_block_given(sexp, level)
      when :alias_native
        return handle_alias_native(sexp) if @scope.class_scope?
      when :require
        path = arglist[1]

        if path and path[0] == :str
          @requires << path[1]
        end

        return "//= require #{path[1]}"
      when :respond_to?
        return handle_respond_to(sexp, level)
      end

      splat = arglist[1..-1].any? { |a| a.first == :splat }

      if Array === arglist.last and arglist.last.first == :block_pass
        block   = process s(:js_tmp, process(arglist.pop, :expr)), :expr
      elsif iter
        block   = iter
      end

      recv ||= s(:self)

      if block
        tmprecv = @scope.new_temp
      elsif splat and recv != [:self] and recv[0] != :lvar
        tmprecv = @scope.new_temp
      end

      args      = ""

      recv_code = process recv, :recv

      args = process arglist, :expr

      result = if block
        # dispatch = "(%s = %s, %s%s._p = %s, %s%s" %
          # [tmprecv, recv_code, tmprecv, mid, block, tmprecv, mid]
        dispatch = "(%s = %s, %s%s._p = %s, %s%s" %
          [tmprecv, recv_code, tmprecv, mid_to_jsid(meth.to_s, false), block, tmprecv, mid]

        if splat
          "%s.apply(null, %s))" % [dispatch, args]
        else
          "%s(%s))" % [dispatch, args]
        end
      else
        # m_missing = " || __mm(#{meth.to_s.inspect})"
        # dispatch = "((#{tmprecv} = #{recv_code}).$m#{mid}#{ m_missing })"
        # splat ? "#{dispatch}.apply(null, #{args})" : "#{dispatch}(#{args})"
        dispatch = tmprecv ? "(#{tmprecv} = #{recv_code})#{mid}" : "#{recv_code}#{mid}"
        splat ? "#{dispatch}.apply(#{tmprecv || recv_code}, #{args})" : "#{dispatch}(#{args})"
      end

      result
    end
  end
end