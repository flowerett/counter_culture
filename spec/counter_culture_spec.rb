require File.expand_path(File.dirname(__FILE__) + '/spec_helper')
require 'database_cleaner'
DatabaseCleaner.strategy = :deletion

describe "CounterCulture" do
  before(:each) do
    DatabaseCleaner.clean
  end

  describe 'create' do
    it "should increment counter cache" do
      user = User.create
      product = Product.create

      expect(user.reviews_count).to eq 0
      expect(product.reviews_count).to eq 0
      expect(user.review_approvals_count).to eq 0

      user.reviews.create :user_id => user.id, :product_id => product.id, :approvals => 13

      user.reload
      product.reload

      expect(user.reviews_count).to eq 1
      expect(user.review_approvals_count).to eq 13
      expect(product.reviews_count).to eq 1
    end

    it "should increment second-level counter cache" do
      company = Company.create
      user = User.create :manages_company_id => company.id
      product = Product.create

      expect(company.reviews_count).to eq 0
      expect(user.reviews_count).to eq 0
      expect(product.reviews_count).to eq 0
      expect(company.review_approvals_count).to eq 0

      review = Review.create :user_id => user.id, :product_id => product.id, :approvals => 314

      company.reload
      user.reload
      product.reload

      expect(company.reviews_count).to eq 1
      expect(company.review_approvals_count).to eq 314
      expect(user.reviews_count).to eq 1
      expect(product.reviews_count).to eq 1
    end

    it "should increment third-level counter cache" do
      industry = Industry.create
      company = Company.create :industry_id => industry.id
      user = User.create :manages_company_id => company.id
      product = Product.create

      expect(industry.reviews_count).to eq 0
      expect(industry.review_approvals_count).to eq 0
      expect(company.reviews_count).to eq 0
      expect(user.reviews_count).to eq 0
      expect(product.reviews_count).to eq 0

      review = Review.create :user_id => user.id, :product_id => product.id, :approvals => 42

      industry.reload
      company.reload
      user.reload
      product.reload

      expect(industry.reviews_count).to eq 1
      expect(industry.review_approvals_count).to eq 42
      expect(company.reviews_count).to eq 1
      expect(user.reviews_count).to eq 1
      expect(product.reviews_count).to eq 1
    end

    it "should increment custom counter cache column" do
      user = User.create
      product = Product.create

      expect(product.rexiews_count).to eq 0

      review = Review.create :user_id => user.id, :product_id => product.id

      product.reload

      expect(product.rexiews_count).to eq 1
    end

    it "should increment third-level custom counter cache" do
      industry = Industry.create
      company = Company.create :industry_id => industry.id
      user = User.create :manages_company_id => company.id
      product = Product.create

      expect(industry.rexiews_count).to eq 0

      review = Review.create :user_id => user.id, :product_id => product.id

      industry.reload

      expect(industry.rexiews_count).to eq 1
    end

    it "should handle nil column name in custom counter cache" do
      user = User.create
      product = Product.create

      expect(user.using_count).to eq 0
      expect(user.tried_count).to eq 0

      review = Review.create :user_id => user.id, :product_id => product.id, :review_type => nil

      user.reload

      expect(user.using_count).to eq 0
      expect(user.tried_count).to eq 0
    end

    it "should increment dynamic counter cache" do
      user = User.create
      product = Product.create

      expect(user.using_count).to eq 0
      expect(user.tried_count).to eq 0

      review_using = Review.create :user_id => user.id, :product_id => product.id, :review_type => 'using'

      user.reload

      expect(user.using_count).to eq 1
      expect(user.tried_count).to eq 0

      review_tried = Review.create :user_id => user.id, :product_id => product.id, :review_type => 'tried'

      user.reload

      expect(user.using_count).to eq 1
      expect(user.tried_count).to eq 1
    end

    it "increments third-level dynamic counter cache" do
      industry = Industry.create
      company = Company.create :industry_id => industry.id
      user = User.create :manages_company_id => company.id
      product = Product.create

      expect(industry.using_count).to eq 0
      expect(industry.tried_count).to eq 0

      review_using = Review.create :user_id => user.id, :product_id => product.id, :review_type => 'using'

      industry.reload

      expect(industry.using_count).to eq 1
      expect(industry.tried_count).to eq 0

      review_tried = Review.create :user_id => user.id, :product_id => product.id, :review_type => 'tried'

      industry.reload

      expect(industry.using_count).to eq 1
      expect(industry.tried_count).to eq 1
    end

    it "should overwrite foreign-key values" do
      3.times { Category.create }
      Category.all {|category| expect(category.products_count).to eq 0 }

      product = Product.create :category_id => Category.first.id
      Category.all {|category| expect(category.products_count).to eq 1 }
    end

    it 'should increment polymorphic counter cache' do
      user = User.create
      company = Company.create

      expect(user.reload.images_count).to eq 0
      expect(company.reload.images_count).to eq 0

      Image.create :owner => user
      Image.create :owner => company

      expect(user.reload.images_count).to eq 1
      expect(company.reload.images_count).to eq 1
    end

    it 'should increment two-level polymorphic counter cache' do
      user = User.create
      company = Company.create

      expect(user.reload.marks_count).to eq 0
      expect(company.reload.marks_count).to eq 0

      ui = Image.create :owner => user
      ci = Image.create :owner => company
      uv = Video.create :owner => user
      cv = Video.create :owner => company

      Mark.create :mark_out => ui
      Mark.create :mark_out => ci
      Mark.create :mark_out => uv
      Mark.create :mark_out => cv

      expect(ui.reload.marks_count).to eq 1
      expect(ci.reload.marks_count).to eq 1
      expect(uv.reload.marks_count).to eq 1
      expect(cv.reload.marks_count).to eq 1
      expect(user.reload.marks_count).to eq 2
      expect(company.reload.marks_count).to eq 2
    end
  end

  describe 'destroy' do
    it "should decrement counter cache" do
      user = User.create
      product = Product.create

      expect(user.reviews_count).to eq 0
      expect(product.reviews_count).to eq 0
      expect(user.review_approvals_count).to eq 0

      review = Review.create :user_id => user.id, :product_id => product.id, :approvals => 69

      user.reload
      product.reload

      expect(user.reviews_count).to eq 1
      expect(product.reviews_count).to eq 1
      expect(user.review_approvals_count).to eq 69

      review.destroy

      user.reload
      product.reload

      expect(user.reviews_count).to eq 0
      expect(user.review_approvals_count).to eq 0
      expect(product.reviews_count).to eq 0
    end

    it "should decrement second-level counter cache" do
      company = Company.create
      user = User.create :manages_company_id => company.id
      product = Product.create

      expect(company.reviews_count).to eq 0
      expect(user.reviews_count).to eq 0
      expect(product.reviews_count).to eq 0
      expect(company.review_approvals_count).to eq 0

      review = Review.create :user_id => user.id, :product_id => product.id, :approvals => 314

      user.reload
      product.reload
      company.reload

      expect(user.reviews_count).to eq 1
      expect(product.reviews_count).to eq 1
      expect(company.reviews_count).to eq 1
      expect(company.review_approvals_count).to eq 314

      review.destroy

      user.reload
      product.reload
      company.reload

      expect(user.reviews_count).to eq 0
      expect(product.reviews_count).to eq 0
      expect(company.reviews_count).to eq 0
      expect(company.review_approvals_count).to eq 0
    end

    it "should decrement third-level counter cache" do
      industry = Industry.create
      company = Company.create :industry_id => industry.id
      user = User.create :manages_company_id => company.id
      product = Product.create

      expect(industry.reviews_count).to eq 0
      expect(industry.review_approvals_count).to eq 0
      expect(company.reviews_count).to eq 0
      expect(user.reviews_count).to eq 0
      expect(product.reviews_count).to eq 0

      review = Review.create :user_id => user.id, :product_id => product.id, :approvals => 42

      industry.reload
      company.reload
      user.reload
      product.reload

      expect(industry.reviews_count).to eq 1
      expect(industry.review_approvals_count).to eq 42
      expect(company.reviews_count).to eq 1
      expect(user.reviews_count).to eq 1
      expect(product.reviews_count).to eq 1

      review.destroy

      industry.reload
      company.reload
      user.reload
      product.reload

      expect(industry.reviews_count).to eq 0
      expect(industry.review_approvals_count).to eq 0
      expect(company.reviews_count).to eq 0
      expect(user.reviews_count).to eq 0
      expect(product.reviews_count).to eq 0
    end

    it "should decrements custom counter cache column" do
      user = User.create
      product = Product.create

      expect(product.rexiews_count).to eq 0

      review = Review.create :user_id => user.id, :product_id => product.id

      product.reload

      expect(product.rexiews_count).to eq 1

      review.destroy

      product.reload

      expect(product.rexiews_count).to eq 0
    end

    it "should decrement third-level custom counter cache" do
      industry = Industry.create
      company = Company.create :industry_id => industry.id
      user = User.create :manages_company_id => company.id
      product = Product.create

      expect(industry.rexiews_count).to eq 0

      review = Review.create :user_id => user.id, :product_id => product.id

      industry.reload
      expect(industry.rexiews_count).to eq 1

      review.destroy

      industry.reload
      expect(industry.rexiews_count).to eq 0
    end

    it "should handle nil column name in custom counter cache" do
      user = User.create
      product = Product.create

      expect(user.using_count).to eq 0
      expect(user.tried_count).to eq 0

      review = Review.create :user_id => user.id, :product_id => product.id, :review_type => nil

      product.reload

      expect(user.using_count).to eq 0
      expect(user.tried_count).to eq 0

      review.destroy

      product.reload

      expect(user.using_count).to eq 0
      expect(user.tried_count).to eq 0
    end

    it "decrements dynamic counter cache" do
      user = User.create
      product = Product.create

      expect(user.using_count).to eq 0
      expect(user.tried_count).to eq 0

      review_using = Review.create :user_id => user.id, :product_id => product.id, :review_type => 'using'

      user.reload

      expect(user.using_count).to eq 1
      expect(user.tried_count).to eq 0

      review_tried = Review.create :user_id => user.id, :product_id => product.id, :review_type => 'tried'

      user.reload

      expect(user.using_count).to eq 1
      expect(user.tried_count).to eq 1

      review_tried.destroy

      user.reload

      expect(user.using_count).to eq 1
      expect(user.tried_count).to eq 0

      review_using.destroy

      user.reload

      expect(user.using_count).to eq 0
      expect(user.tried_count).to eq 0
    end

    it "decrements third-level custom counter cache" do
      industry = Industry.create
      company = Company.create :industry_id => industry.id
      user = User.create :manages_company_id => company.id
      product = Product.create

      expect(industry.using_count).to eq 0
      expect(industry.tried_count).to eq 0

      review_using = Review.create :user_id => user.id, :product_id => product.id, :review_type => 'using'

      industry.reload

      expect(industry.using_count).to eq 1
      expect(industry.tried_count).to eq 0

      review_tried = Review.create :user_id => user.id, :product_id => product.id, :review_type => 'tried'

      industry.reload

      expect(industry.using_count).to eq 1
      expect(industry.tried_count).to eq 1

      review_tried.destroy

      industry.reload

      expect(industry.using_count).to eq 1
      expect(industry.tried_count).to eq 0

      review_using.destroy

      industry.reload

      expect(industry.using_count).to eq 0
      expect(industry.tried_count).to eq 0
    end

    it "should overwrite foreign-key values" do
      3.times { Category.create }
      Category.all {|category| expect(category.products_count).to eq 0 }

      product = Product.create :category_id => Category.first.id
      Category.all {|category| expect(category.products_count).to eq 1 }

      product.destroy
      Category.all {|category| expect(category.products_count).to eq 0 }
    end

    it 'should decrement polymorphic counter cache' do
      user = User.create
      company = Company.create

      expect(user.reload.images_count).to eq 0
      expect(company.reload.images_count).to eq 0

      user_image = Image.create :owner => user

      company_image = Image.create :owner => company

      expect(user.reload.images_count).to eq 1
      expect(company.reload.images_count).to eq 1

      user_image.destroy
      company_image.destroy

       expect(user.reload.images_count).to eq 0
      expect(company.reload.images_count).to eq 0
    end

    it 'should increment two-level polymorphic counter cache' do
      user = User.create
      company = Company.create

      expect(user.reload.marks_count).to eq 0
      expect(company.reload.marks_count).to eq 0

      ui = Image.create :owner => user
      ci = Image.create :owner => company
      uv = Video.create :owner => user
      cv = Video.create :owner => company

      m_ui = Mark.create :mark_out => ui
      m_ci = Mark.create :mark_out => ci
      m_uv =Mark.create :mark_out => uv
      m_cv =Mark.create :mark_out => cv

      expect(ui.reload.marks_count).to eq 1
      expect(ci.reload.marks_count).to eq 1
      expect(uv.reload.marks_count).to eq 1
      expect(cv.reload.marks_count).to eq 1
      expect(user.reload.marks_count).to eq 2
      expect(company.reload.marks_count).to eq 2

      m_cv.destroy
      m_ui.destroy

      expect(ui.reload.marks_count).to eq 0
      expect(ci.reload.marks_count).to eq 1
      expect(uv.reload.marks_count).to eq 1
      expect(cv.reload.marks_count).to eq 0
      expect(user.reload.marks_count).to eq 1
      expect(company.reload.marks_count).to eq 1
    end
  end

  describe 'update' do
    it 'should perform simple update' do
      user1 = User.create
      user2 = User.create
      product = Product.create
      review = Review.create :user_id => user1.id, :product_id => product.id

      review.user = user2
      review.save!

      expect(user1.reload.reviews_count).to eq 0
      expect(user2.reload.reviews_count).to eq 1
    end

    it "should update counter cache" do
      user1 = User.create
      user2 = User.create
      product = Product.create

      expect(user1.reviews_count).to eq 0
      expect(user2.reviews_count).to eq 0
      expect(product.reviews_count).to eq 0
      expect(user1.review_approvals_count).to eq 0
      expect(user2.review_approvals_count).to eq 0

      review = Review.create :user_id => user1.id, :product_id => product.id, :approvals => 42

      user1.reload
      user2.reload
      product.reload

      expect(user1.reviews_count).to eq 1
      expect(user2.reviews_count).to eq 0
      expect(product.reviews_count).to eq 1
      expect(user1.review_approvals_count).to eq 42
      expect(user2.review_approvals_count).to eq 0

      review.user = user2
      review.save!

      user1.reload
      user2.reload
      product.reload

      expect(user1.reviews_count).to eq 0
      expect(user2.reviews_count).to eq 1
      expect(product.reviews_count).to eq 1
      expect(user1.review_approvals_count).to eq 0
      expect(user2.review_approvals_count).to eq 42

      review.update_attribute(:approvals, 69)
      expect(user2.reload.review_approvals_count).to eq 69
    end

    it "should update second-level counter cache" do
      company1 = Company.create
      company2 = Company.create
      user1 = User.create :manages_company_id => company1.id
      user2 = User.create :manages_company_id => company2.id
      product = Product.create

      expect(user1.reviews_count).to eq 0
      expect(user2.reviews_count).to eq 0
      expect(company1.reviews_count).to eq 0
      expect(company2.reviews_count).to eq 0
      expect(product.reviews_count).to eq 0
      expect(company1.review_approvals_count).to eq 0
      expect(company2.review_approvals_count).to eq 0

      review = Review.create :user_id => user1.id, :product_id => product.id, :approvals => 69

      user1.reload
      user2.reload
      company1.reload
      company2.reload
      product.reload

      expect(user1.reviews_count).to eq 1
      expect(user2.reviews_count).to eq 0
      expect(company1.reviews_count).to eq 1
      expect(company2.reviews_count).to eq 0
      expect(product.reviews_count).to eq 1
      expect(company1.review_approvals_count).to eq 69
      expect(company2.review_approvals_count).to eq 0

      review.user = user2
      review.save!

      user1.reload
      user2.reload
      company1.reload
      company2.reload
      product.reload

      expect(user1.reviews_count).to eq 0
      expect(user2.reviews_count).to eq 1
      expect(company1.reviews_count).to eq 0
      expect(company2.reviews_count).to eq 1
      expect(product.reviews_count).to eq 1
      expect(company1.review_approvals_count).to eq 0
      expect(company2.review_approvals_count).to eq 69

      review.update_attribute(:approvals, 42)
      expect(company2.reload.review_approvals_count).to eq 42
    end

    it "should update third-level counter cache" do
      industry1 = Industry.create
      industry2 = Industry.create
      company1 = Company.create :industry_id => industry1.id
      company2 = Company.create :industry_id => industry2.id
      user1 = User.create :manages_company_id => company1.id
      user2 = User.create :manages_company_id => company2.id
      product = Product.create

      expect(industry1.reviews_count).to eq 0
      expect(industry2.reviews_count).to eq 0
      expect(company1.reviews_count).to eq 0
      expect(company2.reviews_count).to eq 0
      expect(user1.reviews_count).to eq 0
      expect(user2.reviews_count).to eq 0
      expect(industry1.review_approvals_count).to eq 0
      expect(industry2.review_approvals_count).to eq 0

      review = Review.create :user_id => user1.id, :product_id => product.id, :approvals => 42

      industry1.reload
      industry2.reload
      company1.reload
      company2.reload
      user1.reload
      user2.reload

      expect(industry1.reviews_count).to eq 1
      expect(industry2.reviews_count).to eq 0
      expect(company1.reviews_count).to eq 1
      expect(company2.reviews_count).to eq 0
      expect(user1.reviews_count).to eq 1
      expect(user2.reviews_count).to eq 0
      expect(industry1.review_approvals_count).to eq 42
      expect(industry2.review_approvals_count).to eq 0

      review.user = user2
      review.save!

      industry1.reload
      industry2.reload
      company1.reload
      company2.reload
      user1.reload
      user2.reload

      expect(industry1.reviews_count).to eq 0
      expect(industry2.reviews_count).to eq 1
      expect(company1.reviews_count).to eq 0
      expect(company2.reviews_count).to eq 1
      expect(user1.reviews_count).to eq 0
      expect(user2.reviews_count).to eq 1
      expect(industry1.review_approvals_count).to eq 0
      expect(industry2.review_approvals_count).to eq 42

      review.update_attribute(:approvals, 69)
      expect(industry2.reload.review_approvals_count).to eq 69
    end

    it "should update custom counter cache column" do
      user = User.create
      product1 = Product.create
      product2 = Product.create

      expect(product1.rexiews_count).to eq 0
      expect(product2.rexiews_count).to eq 0

      review = Review.create :user_id => user.id, :product_id => product1.id

      product1.reload
      product2.reload

      expect(product1.rexiews_count).to eq 1
      expect(product2.rexiews_count).to eq 0

      review.product = product2
      review.save!

      product1.reload
      product2.reload

      expect(product1.rexiews_count).to eq 0
      expect(product2.rexiews_count).to eq 1
    end

    it "updates third-level custom counter cache" do
      industry1 = Industry.create
      industry2 = Industry.create
      company1 = Company.create :industry_id => industry1.id
      company2 = Company.create :industry_id => industry2.id
      user1 = User.create :manages_company_id => company1.id
      user2 = User.create :manages_company_id => company2.id
      product = Product.create

      expect(industry1.using_count).to eq 0
      expect(industry1.tried_count).to eq 0
      expect(industry2.using_count).to eq 0
      expect(industry2.tried_count).to eq 0

      review_using = Review.create :user_id => user1.id, :product_id => product.id, :review_type => 'using'

      industry1.reload
      industry2.reload

      expect(industry1.using_count).to eq 1
      expect(industry1.tried_count).to eq 0
      expect(industry2.using_count).to eq 0
      expect(industry2.tried_count).to eq 0

      review_tried = Review.create :user_id => user1.id, :product_id => product.id, :review_type => 'tried'

      industry1.reload
      industry2.reload

      expect(industry1.using_count).to eq 1
      expect(industry1.tried_count).to eq 1
      expect(industry2.using_count).to eq 0
      expect(industry2.tried_count).to eq 0

      review_tried.user = user2
      review_tried.save!

      industry1.reload
      industry2.reload

      expect(industry1.using_count).to eq 1
      expect(industry1.tried_count).to eq 0
      expect(industry2.using_count).to eq 0
      expect(industry2.tried_count).to eq 1

      review_using.user = user2
      review_using.save!

      industry1.reload
      industry2.reload

      expect(industry1.using_count).to eq 0
      expect(industry1.tried_count).to eq 0
      expect(industry2.using_count).to eq 1
      expect(industry2.tried_count).to eq 1
    end

    it "handles nil column name in custom counter cache" do
      product = Product.create
      user1 = User.create
      user2 = User.create

      expect(user1.using_count).to eq 0
      expect(user1.tried_count).to eq 0
      expect(user2.using_count).to eq 0
      expect(user2.tried_count).to eq 0

      review = Review.create :user_id => user1.id, :product_id => product.id, :review_type => nil

      user1.reload
      user2.reload

      expect(user1.using_count).to eq 0
      expect(user1.tried_count).to eq 0
      expect(user2.using_count).to eq 0
      expect(user2.tried_count).to eq 0

      review.user = user2
      review.save!

      user1.reload
      user2.reload

      expect(user1.using_count).to eq 0
      expect(user1.tried_count).to eq 0
      expect(user2.using_count).to eq 0
      expect(user2.tried_count).to eq 0
    end

    context "conditional counts" do
      let(:product) {Product.create!}
      let(:user) {User.create!}

      it "should increment and decrement if changing column name" do
        expect(user.using_count).to eq 0
        expect(user.tried_count).to eq 0

        review = Review.create :user_id => user.id, :product_id => product.id, :review_type => "using"
        user.reload

        expect(user.using_count).to eq 1
        expect(user.tried_count).to eq 0

        review.review_type = "tried"
        review.save!

        user.reload

        expect(user.using_count).to eq 0
        expect(user.tried_count).to eq 1
      end

      it "should increment if changing from a nil column name" do
        expect(user.using_count).to eq 0
        expect(user.tried_count).to eq 0

        review = Review.create :user_id => user.id, :product_id => product.id, :review_type => nil
        user.reload

        expect(user.using_count).to eq 0
        expect(user.tried_count).to eq 0

        review.review_type = "tried"
        review.save!

        user.reload

        expect(user.using_count).to eq 0
        expect(user.tried_count).to eq 1
      end

      it "should decrement if changing column name to nil" do
        expect(user.using_count).to eq 0
        expect(user.tried_count).to eq 0

        review = Review.create :user_id => user.id, :product_id => product.id, :review_type => "using"
        user.reload

        expect(user.using_count).to eq 1
        expect(user.tried_count).to eq 0

        review.review_type = nil
        review.save!

        user.reload

        expect(user.using_count).to eq 0
        expect(user.tried_count).to eq 0
      end
    end

    it "should overwrite foreign-key values" do
      3.times { Category.create }
      Category.all {|category| expect(category.products_count).to eq 0 }

      product = Product.create :category_id => Category.first.id
      Category.all {|category| expect(category.products_count).to eq 1 }

      product.category = nil
      product.save!
      Category.all {|category| expect(category.products_count).to eq 0 }
    end

    it 'should update polymorphic counter cache' do
      user = User.create
      company = Company.create

      expect(user.reload.images_count).to eq 0
      expect(company.reload.images_count).to eq 0

      user_image = Image.create :owner => user
      company_image = Image.create :owner => company

      expect(user.reload.images_count).to eq 1
      expect(company.reload.images_count).to eq 1

      user_image.owner = company
      user_image.save!

      expect(user.reload.images_count).to eq 0
      expect(company.reload.images_count).to eq 2
    end

    it 'should update two-level polymorphic counter cache' do
      user = User.create
      company = Company.create

      expect(user.reload.marks_count).to eq 0
      expect(company.reload.marks_count).to eq 0

      ui = Image.create :owner => user
      ci = Image.create :owner => company
      uv = Video.create :owner => user
      cv = Video.create :owner => company

      m_ui = Mark.create :mark_out => ui
      m_ci = Mark.create :mark_out => ci
      m_uv = Mark.create :mark_out => uv
      m_cv = Mark.create :mark_out => cv

      expect(ui.reload.marks_count).to eq 1
      expect(ci.reload.marks_count).to eq 1
      expect(uv.reload.marks_count).to eq 1
      expect(cv.reload.marks_count).to eq 1
      expect(user.reload.marks_count).to eq 2
      expect(company.reload.marks_count).to eq 2

      m_cv.mark_out = ui
      m_cv.save!

      expect(ui.reload.marks_count).to eq 2
      expect(ci.reload.marks_count).to eq 1
      expect(uv.reload.marks_count).to eq 1
      expect(cv.reload.marks_count).to eq 0
      expect(user.reload.marks_count).to eq 3
      expect(company.reload.marks_count).to eq 1
    end
  end

  describe 'delta column' do
    it "should treats null delta column values as 0" do
      user = User.create
      product = Product.create

      expect(user.reviews_count).to eq 0
      expect(product.reviews_count).to eq 0
      expect(user.review_approvals_count).to eq 0

      review = Review.create :user_id => user.id, :product_id => product.id, :approvals => nil

      user.reload
      product.reload

      expect(user.reviews_count).to eq 1
      expect(user.review_approvals_count).to eq 0
      expect(product.reviews_count).to eq 1
    end
  end

  context 'custom properties' do
    it "should work correctly for relationships with custom names" do
      company = Company.create
      user1 = User.create :manages_company_id => company.id

      company.reload
      expect(company.managers_count).to eq 1

      user2 = User.create :manages_company_id => company.id

      company.reload
      expect(company.managers_count).to eq 2

      user2.destroy

      company.reload
      expect(company.managers_count).to eq 1

      company2 = Company.create
      user1.manages_company_id = company2.id
      user1.save!

      company.reload
      expect(company.managers_count).to eq 0
    end

    it "should work correctly with string keys" do
      string_id = HasStringId.create(id: "1")
      string_id2 = HasStringId.create(id: "abc")

      user = User.create :has_string_id_id => string_id.id

      string_id.reload
      expect(string_id.users_count).to eq 1

      user2 = User.create :has_string_id_id => string_id.id

      string_id.reload
      expect(string_id.users_count).to eq 2

      user2.has_string_id_id = string_id2.id
      user2.save!

      string_id.reload
      string_id2.reload
      expect(string_id.users_count).to eq 1
      expect(string_id2.users_count).to eq 1

      user2.destroy
      string_id.reload
      string_id2.reload
      expect(string_id.users_count).to eq 1
      expect(string_id2.users_count).to eq 0

      user.destroy
      string_id.reload
      string_id2.reload
      expect(string_id.users_count).to eq 0
      expect(string_id2.users_count).to eq 0
    end




    it "should correctly sum up float values" do
      user = User.create

      r1 = Review.create :user_id => user.id, :value => 3.4

      user.reload
      expect(user.review_value_sum.round(1)).to eq 3.4

      r2 = Review.create :user_id => user.id, :value => 7.2

      user.reload
      expect(user.review_value_sum.round(1)).to eq 10.6

      r3 = Review.create :user_id => user.id, :value => 5

      user.reload
      expect(user.review_value_sum.round(1)).to eq 15.6

      r2.destroy

      user.reload
      expect(user.review_value_sum.round(1)).to eq 8.4

      r3.destroy

      user.reload
      expect(user.review_value_sum.round(1)).to eq 3.4

      r1.destroy

      user.reload
      expect(user.review_value_sum.round(1)).to eq 0
    end

    it "should update the timestamp if touch: true is set" do
      user = User.create
      product = Product.create

      sleep 1

      review = Review.create :user_id => user.id, :product_id => product.id

      user.reload; product.reload

      expect(user.created_at.to_i).to eq user.updated_at.to_i
      expect(product.created_at.to_i).to be < product.updated_at.to_i
    end

    it "should update counts correctly when creating using nested attributes" do
      user = User.create(:reviews_attributes => [{:some_text => 'abc'}, {:some_text => 'xyz'}])
      user.reload
      expect(user.reviews_count).to eq 2
    end

    it "should use relation primary_key correctly", :focus => true do
      subcateg = Subcateg.create :subcat_id => Subcateg::SUBCAT_1
      post = Post.new
      post.subcateg = subcateg
      post.save!
      subcateg.reload
      expect(subcateg.posts_count).to eq 1
    end
  end



  describe "#previous_model" do
    let(:user){User.create :name => "John Smith", :manages_company_id => 1}

    it "should return a copy of the original model" do
      user.name = "Joe Smith"
      user.manages_company_id = 2
      prev = user.send(:previous_model)

      expect(prev.name).to eq "John Smith"
      expect(prev.manages_company_id).to eq 1

      expect(user.name).to eq "Joe Smith"
      expect(user.manages_company_id).to eq 2
    end
  end

  describe "self referential counter cache" do
    it "increments counter cache on create" do
      company = Company.create!
      company.children << Company.create!

      company.reload
      expect(company.children_count).to eq 1
    end

    it "decrements counter cache on destroy" do
      company = Company.create!
      company.children << Company.create!

      company.reload
      expect(company.children_count).to eq 1

      company.children.first.destroy

      company.reload
      expect(company.children_count).to eq 0
    end
  end
end
