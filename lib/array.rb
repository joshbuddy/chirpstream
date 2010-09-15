class Array
	def in_groups_of(number, fill_with = nil)
		if fill_with == false
			collection = self
		else
			# size % number gives how many extra we have;
			# subtracting from number gives how many to add;
			# modulo number ensures we don't add group of just fill.
			padding = (number - size % number) % number
			collection = dup.concat([fill_with] * padding)
		end

		if block_given?
			collection.each_slice(number) { |slice| yield(slice) }
		else
			groups = []
			collection.each_slice(number) { |group| groups << group }
			groups
		end
	end
	def in_groups(number, fill_with = nil)
		# size / number gives minor group size;
		# size % number gives how many objects need extra accommodation;
		# each group hold either division or division + 1 items.
		division = size / number
		modulo = size % number

		# create a new array avoiding dup
		groups = []
		start = 0

		number.times do |index|
			length = division + (modulo > 0 && modulo > index ? 1 : 0)
			padding = fill_with != false &&
				modulo > 0 && length == division ? 1 : 0
			groups << slice(start, length).concat([fill_with] * padding)
			start += length
		end

		if block_given?
			groups.each { |g| yield(g) }
		else
			groups
		end
	end
end
